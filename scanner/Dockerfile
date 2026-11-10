# BrandGuard lookalike domain scanner (local demo).
# Wraps the open-source dnstwist engine (Apache 2.0) in a small internal HTTP
# service that N8N calls. No secrets are stored in this image.
FROM python:3.12-slim

# Pinned versions; pip itself is removed afterwards so the running image
# carries no package installer (smaller attack surface).
RUN pip install --no-cache-dir dnstwist==20250130 dnspython==2.7.0 idna==3.10 tld==0.13 \
 && pip uninstall -y pip

WORKDIR /app
COPY app.py words.txt tlds.txt ./

USER nobody
EXPOSE 8080
CMD ["python", "-I", "/app/app.py"]
