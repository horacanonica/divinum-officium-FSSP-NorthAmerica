FROM debian:latest

RUN apt-get update && apt-get install -y \
    libcgi-pm-perl \
    libcgi-session-perl \
    bsdmainutils \
    zip \
    libwww-perl \
    dos2unix \
    python3 \
    python3-pip \
    && pip3 install --break-system-packages fastapi uvicorn python-multipart \
    && apt-get --purge remove -y dos2unix \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY epubweb/main.py /app/main.py
COPY epubweb/gen_all.py /app/gen_all.py

# In local dev these are bind-mounted; baked in for Fly.io / production.
COPY web /var/www/web
COPY standalone/tools/epubgen2 /var/www/standalone/tools/epubgen2

CMD ["python3", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8090"]
