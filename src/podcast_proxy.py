#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Separater HTTP-Proxy für Podcast-Streaming.
Läuft als eigener Prozess, UI bleibt frei.
"""

import sys
import os
import socket
import subprocess
import threading
import time
import re

def log(msg):
    """Log mit Timestamp zu stderr"""
    sys.stderr.write("[PROXY] %s\n" % msg)
    sys.stderr.flush()

def get_content_length(url):
    """Hole Content-Length via wget --spider"""
    try:
        proc = subprocess.Popen(
            ['/opt/wunderw/bin/wget', '--spider', '-S', '-q', url],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        _, stderr = proc.communicate()
        
        for line in stderr.split('\n'):
            if 'content-length:' in line.lower():
                parts = line.lower().split('content-length:')
                if len(parts) > 1:
                    try:
                        return int(parts[1].strip())
                    except:
                        pass
    except:
        pass
    return None

def run_proxy(url):
    """Starte HTTP-Proxy für URL"""
    
    log("Starting proxy for: %s" % url[:80])
    
    # Hole Content-Length
    content_length = get_content_length(url)
    if not content_length:
        content_length = 50 * 1024 * 1024  # 50MB fallback
    
    log("Content-Length: %d" % content_length)
    
    # Cache-Verzeichnis
    cache_dir = "/home/user/.oe1cache"
    if not os.path.exists(cache_dir):
        os.makedirs(cache_dir)
    
    # Lösche alte Dateien
    for f in os.listdir(cache_dir):
        if f.startswith('podcast_') and f.endswith('.mp3'):
            try:
                os.remove(os.path.join(cache_dir, f))
            except:
                pass
    
    temp_file = os.path.join(cache_dir, "podcast_%d.mp3" % int(time.time()))
    log("Temp file: %s" % temp_file)
    
    # Starte wget Download
    download_proc = subprocess.Popen(
        ['/opt/wunderw/bin/wget', '-q', '-O', temp_file, url],
        stdout=open('/dev/null', 'w'),
        stderr=open('/dev/null', 'w')
    )
    log("wget started, PID %d" % download_proc.pid)
    
    # Warte auf initiale Daten
    min_buffer = 100 * 1024  # 100KB
    log("Waiting for initial buffer (%d bytes)..." % min_buffer)
    
    for i in range(100):  # Max 10 Sekunden
        if os.path.exists(temp_file):
            size = os.path.getsize(temp_file)
            if size >= min_buffer:
                log("Initial buffer ready: %d bytes" % size)
                break
            # Download fertig?
            if download_proc.poll() is not None:
                log("Download complete: %d bytes" % size)
                break
        time.sleep(0.1)
    
    if not os.path.exists(temp_file):
        log("ERROR: temp file not created!")
        return
    
    init_size = os.path.getsize(temp_file)
    log("Initial file size: %d bytes" % init_size)
    
    # Starte HTTP-Server
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('127.0.0.1', 0))
    sock.listen(5)
    port = sock.getsockname()[1]
    
    # Gib Port an Parent zurück (über stdout)
    print "PORT:%d" % port
    print "SIZE:%d" % content_length
    sys.stdout.flush()
    
    log("HTTP server on port %d" % port)
    
    running = True
    
    def handle_client(client):
        log("Client connected")
        try:
            request = client.recv(4096)
            log("Request: %s" % request[:100].replace('\r\n', ' | '))
            
            # Parse Range-Header
            range_start = 0
            match = re.search(r'Range:\s*bytes=(\d+)-', request, re.IGNORECASE)
            if match:
                range_start = int(match.group(1))
                log("Range request: start=%d" % range_start)
            
            # Warte auf Daten falls nötig
            if range_start == 0:
                for _ in range(50):
                    if os.path.exists(temp_file) and os.path.getsize(temp_file) >= 100000:
                        break
                    time.sleep(0.1)
            
            if not os.path.exists(temp_file):
                log("ERROR: temp file gone!")
                client.close()
                return
            
            file_size = os.path.getsize(temp_file)
            total_size = content_length or file_size
            log("File size: %d, total: %d" % (file_size, total_size))
            
            # HTTP Response - verwende Chunked Transfer für besseres Streaming
            header = "HTTP/1.1 200 OK\r\n"
            header += "Content-Type: audio/mpeg\r\n"
            header += "Transfer-Encoding: chunked\r\n"
            header += "Accept-Ranges: none\r\n"
            header += "Connection: keep-alive\r\n\r\n"
            
            log("Sending chunked header...")
            client.sendall(header)
            log("Header sent")
            
            # Stream aus Datei mit Chunked Encoding
            with open(temp_file, 'rb') as f:
                f.seek(range_start)
                bytes_sent = 0
                
                while running:
                    # Warte auf mehr Daten wenn nötig
                    current_pos = range_start + bytes_sent
                    
                    if download_proc.poll() is None:  # Download läuft noch
                        file_size = os.path.getsize(temp_file)
                        wait_count = 0
                        while file_size <= current_pos and wait_count < 50:
                            time.sleep(0.1)
                            file_size = os.path.getsize(temp_file)
                            if download_proc.poll() is not None:
                                break
                            wait_count += 1
                    
                    chunk = f.read(65536)
                    if chunk:
                        try:
                            # Chunked encoding: size in hex, dann data, dann CRLF
                            chunk_header = "%x\r\n" % len(chunk)
                            client.sendall(chunk_header + chunk + "\r\n")
                            bytes_sent += len(chunk)
                            if bytes_sent % (1024*1024) < 65536:
                                log("Sent %d bytes" % bytes_sent)
                        except Exception as e:
                            log("Send error: %s" % e)
                            break
                    else:
                        # Keine Daten - warte oder beende
                        if download_proc.poll() is not None:
                            # Download fertig - sende final chunk
                            try:
                                client.sendall("0\r\n\r\n")
                                log("Final chunk sent")
                            except:
                                pass
                            break
                        else:
                            time.sleep(0.1)
                
                log("Stream ended, sent %d bytes total" % bytes_sent)
        except Exception as e:
            log("Client error: %s" % e)
            import traceback
            traceback.print_exc()
        finally:
            try:
                client.close()
            except:
                pass
    
    # Accept-Loop
    sock.settimeout(1.0)
    log("Waiting for connections...")
    while running:
        try:
            client, addr = sock.accept()
            log("Accepted connection from %s" % str(addr))
            t = threading.Thread(target=handle_client, args=(client,))
            t.daemon = True
            t.start()
        except socket.timeout:
            # Prüfe ob Download noch läuft oder Parent-Prozess weg
            if download_proc.poll() is not None:
                # Download fertig - warte noch auf Clients
                time.sleep(5)
                running = False
        except Exception as e:
            log("Accept error: %s" % e)
            break
    
    log("Proxy shutting down")
    
    # Cleanup
    try:
        sock.close()
    except:
        pass
    try:
        download_proc.terminate()
    except:
        pass
    try:
        if os.path.exists(temp_file):
            os.remove(temp_file)
    except:
        pass

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print "Usage: podcast_proxy.py <url>"
        sys.exit(1)
    
    url = sys.argv[1]
    run_proxy(url)
