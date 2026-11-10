"""
BrandGuard lookalike domain scanner (local demo).

An internal HTTP service that N8N calls once per official website domain:

    POST /scan  {"domain": "example.com", "keywords": ["example"], "include_original": false}
    GET  /health

For the domain it:
  1. generates lookalike names with dnstwist (typos, swapped letters,
     look-alike characters, brand + word combinations, other domain endings);
  2. keeps only names that are registered (they exist in DNS);
  3. looks up the registration date and registrar (WHOIS);
  4. opens the home page of each one that has a web address, to see whether
     it is live, redirects elsewhere, is a parked "for sale" page, mentions
     the brand, or shows a password field.

Safety: the page check only reads up to 128 KB of HTML, never runs scripts,
and refuses to connect to private, loopback or link-local addresses, so a
lookalike domain cannot be used to reach machines on the local network.
The address is checked again on the open connection, so a domain cannot pass
the check and then switch to a private address (DNS rebinding).

Access: every /scan request must carry the shared secret from SCANNER_TOKEN
("Authorization: Bearer <token>"). The service refuses to start without it.
"""

import hmac
import html
import http.client
import ipaddress
import json
import os
import ssl
import sys
import re
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import dnstwist

PORT = 8080
MAX_BODY = 10_000
SCANNER_TOKEN = os.environ.get('SCANNER_TOKEN', '')
DOMAIN_RE = re.compile(r'^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$')
# DNS servers for lookups. Empty = the container's own resolver (Docker's
# DNS), which proved more reliable than sending UDP queries straight to
# public resolvers from Docker Desktop. Example: SCANNER_NAMESERVERS=1.1.1.1,8.8.8.8
NAMESERVERS = os.environ.get('SCANNER_NAMESERVERS', '').strip()
THREADS = 48
PAGE_TIMEOUT = 8
PAGE_BYTES = 128 * 1024
USER_AGENT = 'Mozilla/5.0 (BrandGuard brand protection scanner; local demo)'

PARKED_RE = re.compile(
    r'(domain (name )?(is |may be )?for sale|buy this domain|this domain is parked|parked (free|domain)|'
    r'sedoparking|sedo\.com|dan\.com|afternic|hugedomains|undeveloped\.com|parkingcrew|bodis\.com|'
    r'domain has expired|godaddy\.com/domainsearch|this domain name is available)',
    re.I,
)
TITLE_RE = re.compile(r'<title[^>]*>(.*?)</title>', re.I | re.S)
PASSWORD_RE = re.compile(r'<input[^>]+type\s*=\s*["\']?password', re.I)

# dnstwist.run() reads options from sys.argv, so only one scan runs at a time
scan_lock = threading.Lock()


def load_list(path):
    with open(path, encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip() and not line.startswith('#')]


WORDS = load_list('/app/words.txt')
TLDS = load_list('/app/tlds.txt')


def is_public_ip(value):
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return False
    return ip.is_global


def host_is_public(host):
    """True only if every address the host resolves to is a public address."""
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        return False
    addresses = {info[4][0] for info in infos}
    return bool(addresses) and all(is_public_ip(a) for a in addresses)


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    max_redirections = 5

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        host = urllib.parse.urlsplit(newurl).hostname or ''
        if not host_is_public(host):
            raise urllib.error.URLError('redirect to a non-public address blocked')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _checked_connection(address, *args, **kwargs):
    """Open a socket, then refuse it unless the connected peer is public."""
    sock = socket.create_connection(address, *args, **kwargs)
    peer = sock.getpeername()[0]
    if not is_public_ip(peer):
        sock.close()
        raise OSError(f'connection to non-public address {peer} blocked')
    return sock


class SafeHTTPConnection(http.client.HTTPConnection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._create_connection = _checked_connection


class SafeHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._create_connection = _checked_connection


class SafeHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(SafeHTTPConnection, req)


class SafeHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        # Certificates of suspect sites are often invalid; we only read the
        # page as evidence and never send data, so verification is relaxed here.
        return self.do_open(SafeHTTPSConnection, req, context=ssl._create_unverified_context())  # nosec B323


# No proxy handler: requests always go direct, through the checked connection
OPENER = urllib.request.OpenerDirector()
for handler in (SafeHTTPHandler(), SafeHTTPSHandler(), SafeRedirect(), urllib.request.HTTPErrorProcessor(),
                urllib.request.UnknownHandler()):
    OPENER.add_handler(handler)


def check_page(domain, keywords):
    """Fetch the home page once and describe what is there."""
    result = {'web_live': False}
    if not host_is_public(domain):
        result['web_error'] = 'no public web address'
        return result
    for scheme in ('https', 'http'):
        url = f'{scheme}://{domain}/'
        try:
            req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT, 'Accept': 'text/html'})
            with OPENER.open(req, timeout=PAGE_TIMEOUT) as resp:
                body = resp.read(PAGE_BYTES).decode('utf-8', errors='replace')
                final_url = resp.geturl()
                status = resp.status
        except urllib.error.HTTPError as e:
            result.update(web_live=True, web_status=e.code, web_final_url=url)
            return result
        except Exception as e:  # noqa: BLE001 - any network failure means "not reachable on this scheme"
            result['web_error'] = str(e)[:200]
            continue
        title_match = TITLE_RE.search(body)
        title = html.unescape(re.sub(r'\s+', ' ', title_match.group(1))).strip()[:200] if title_match else ''
        # Ignore the page repeating its own domain name (which contains the
        # brand), so only real mentions of the brand count
        lowered = body.lower().replace(domain, ' ')
        final_host = (urllib.parse.urlsplit(final_url).hostname or '').lower()
        result.update(
            web_live=True,
            web_status=status,
            web_final_url=final_url[:500],
            web_final_host=final_host,
            web_title=title,
            web_parked=bool(PARKED_RE.search(body)),
            web_mentions_brand=any(k.lower() in lowered for k in keywords),
            web_password_field=bool(PASSWORD_RE.search(body)),
        )
        result.pop('web_error', None)
        return result
    return result


def clean_records(values):
    return [v for v in (values or []) if v and not str(v).startswith('!')]


def scan(domain, keywords, include_original=False):
    started = time.time()
    with scan_lock:
        fuzz = dnstwist.Fuzzer(domain, dictionary=WORDS, tld_dictionary=TLDS)
        fuzz.generate()
        generated = len(fuzz.domains) - 1  # minus the original domain
        options = dict(
            domain=domain,
            registered=True,
            format='null',
            threads=THREADS,
            whois=True,
            dictionary='/app/words.txt',
            tld='/app/tlds.txt',
        )
        if NAMESERVERS:
            options['nameservers'] = NAMESERVERS
        rows = dnstwist.run(**options)

    found = []
    for row in rows:
        # The scanned name itself is skipped unless the caller asks for it
        # (keyword scans: someone else may own brand.com)
        if (row.get('fuzzer') == '*original' or row.get('domain') == domain) and not include_original:
            continue
        found.append({
            'domain': row['domain'],
            'fuzzer': row.get('fuzzer'),
            'dns_a': clean_records(row.get('dns_a')),
            'dns_aaaa': clean_records(row.get('dns_aaaa')),
            'dns_mx': clean_records(row.get('dns_mx')),
            'dns_ns': clean_records(row.get('dns_ns')),
            'whois_created': row.get('whois_created'),
            'whois_registrar': row.get('whois_registrar'),
        })

    with ThreadPoolExecutor(max_workers=16) as pool:
        pages = list(pool.map(lambda r: check_page(r['domain'], keywords) if (r['dns_a'] or r['dns_aaaa']) else {'web_live': False}, found))
    for r, page in zip(found, pages):
        r.update(page)

    return {
        'domain': domain,
        'generated': generated,
        'registered': found,
        'duration_seconds': round(time.time() - started, 1),
        'engine': f'dnstwist {dnstwist.__version__}',
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/health':
            return self._send(200, {'status': 'ok'})
        self._send(404, {'error': 'not found'})

    def _authorised(self):
        sent = self.headers.get('Authorization', '')
        expected = f'Bearer {SCANNER_TOKEN}'
        return hmac.compare_digest(sent.encode('utf-8'), expected.encode('utf-8'))

    def do_POST(self):
        if self.path != '/scan':
            return self._send(404, {'error': 'not found'})
        if not self._authorised():
            return self._send(401, {'error': 'unauthorised'})
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length < 0 or length > MAX_BODY:
                return self._send(413, {'error': 'request too large'})
            payload = json.loads(self.rfile.read(length) or b'{}')
            if not isinstance(payload, dict):
                raise ValueError('body must be a JSON object')
            domain = str(payload.get('domain', '')).strip().lower()
            keywords = [str(k) for k in payload.get('keywords', []) if str(k).strip()][:10]
            include_original = bool(payload.get('include_original', False))
        except (ValueError, TypeError):
            return self._send(400, {'error': 'body must be JSON: {"domain": "...", "keywords": [...]}'})
        if not DOMAIN_RE.match(domain):
            return self._send(400, {'error': f'invalid domain: {domain[:100]}'})
        if domain.endswith('.bank.in'):
            # Only licensed banks can register .bank.in names, so lookalikes
            # appear on other endings. Callers should scan the .in name.
            return self._send(400, {'error': 'scan the matching .in domain instead of .bank.in'})
        try:
            self._send(200, scan(domain, keywords, include_original))
        except Exception as e:  # noqa: BLE001 - log details, return a generic message
            print(f'scan of {domain} failed: {e!r}', file=sys.stderr, flush=True)
            self._send(500, {'error': 'scan failed; see scanner logs'})

    def log_message(self, fmt, *args):
        print('%s %s' % (self.address_string(), fmt % args), flush=True)


if __name__ == '__main__':
    if len(SCANNER_TOKEN) < 24:
        sys.exit('SCANNER_TOKEN must be set to a random value of at least 24 characters')
    print(f'BrandGuard scanner listening on port {PORT}', flush=True)
    # Listens on all interfaces inside the container only; Docker publishes it
    # to 127.0.0.1 on the host, and /scan requires the shared token.
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()  # nosec B104
