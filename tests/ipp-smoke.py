#!/usr/bin/env python3
"""macOS integration test: real URLSession uploads to a local mock IPP printer.
Run: /usr/bin/python3 tests/ipp-smoke.py
No jobs are sent to a physical printer. CUPS independently decodes the raster.
"""
import gzip
import http.server
import pathlib
import struct
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parent.parent

def attr(tag, name, value):
    name = name.encode()
    if isinstance(value, str):
        value = value.encode()
    return bytes([tag]) + struct.pack('!H', len(name)) + name + struct.pack('!H', len(value)) + value

def parse(body):
    pos, name, attrs = 8, '', {}
    while pos < len(body):
        tag = body[pos]; pos += 1
        if tag == 3:
            return attrs, body[pos:]
        if tag < 16:
            continue
        length = struct.unpack_from('!H', body, pos)[0]; pos += 2
        if length:
            name = body[pos:pos + length].decode()
        pos += length
        length = struct.unpack_from('!H', body, pos)[0]; pos += 2
        attrs[name] = body[pos:pos + length]
        pos += length
    raise AssertionError('missing end tag')

class Printer(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        operation = struct.unpack_from('!H', body, 2)[0]
        attrs, payload = parse(body)
        self.server.operations.append(operation)
        result = b'\x01\x01\x00\x00' + body[4:8] + b'\x01'
        result += attr(0x47, 'attributes-charset', 'utf-8') + attr(0x48, 'attributes-natural-language', 'en')
        if operation == 11:
            result += b'\x04'
            result += attr(0x49, 'document-format-supported', 'image/urf' if self.server.scenario == 'unsupported' else 'image/pwg-raster')
            result += attr(0x44, 'sides-supported', 'two-sided-short-edge')
            result += attr(0x44, 'media-supported', 'na_letter_8.5x11in')
            result += attr(0x44, 'pwg-raster-document-type-supported', 'sgray_8')
            result += attr(0x32, 'pwg-raster-document-resolution-supported', struct.pack('!IIB', 300, 300, 3))
            result += attr(0x44, 'pwg-raster-document-sheet-back', 'normal')
        else:
            assert operation == 2
            assert attrs['document-format'] == b'image/pwg-raster'
            assert attrs['sides'] == b'two-sided-short-edge'
            assert attrs['ipp-attribute-fidelity'] == b'\x01'
            assert payload.startswith(b'RaS2')
            assert len(payload) > 1800
            self.server.raster.write_bytes(payload)
            result += b'\x02' + attr(0x21, 'job-id', struct.pack('!I', 77))
            if self.server.scenario == 'rejected':
                result = result[:2] + b'\x04\x0b' + result[4:]
            if self.server.scenario == 'truncated':
                result = b'\x01'
        result += b'\x03'
        self.send_response(200)
        self.send_header('Content-Type', 'application/ipp')
        self.send_header('Content-Length', str(len(result)))
        self.end_headers()
        self.wfile.write(result)

with tempfile.TemporaryDirectory(prefix='booklet-ipp-test-') as folder:
    folder = pathlib.Path(folder)
    executable = folder / 'ipp-smoke'
    sources = ROOT / 'ios/BookletCore/Sources/BookletCore'
    subprocess.run(['swiftc', '-parse-as-library', str(ROOT / 'tests/ipp-smoke.swift'),
                    str(sources / 'IPPProtocol.swift'), str(sources / 'PWGRasterWriter.swift'),
                    str(sources / 'IPPPrintClient.swift'), '-o', str(executable)], check=True)
    fixture = folder / 'source.pdf'
    raw = pathlib.Path('/usr/share/cups/ipptool/onepage-letter.pdf').read_bytes()
    fixture.write_bytes(gzip.decompress(raw) if raw.startswith(b'\x1f\x8b') else raw)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Printer)
    server.raster = folder / 'output.pwg'
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        for scenario in ['accepted', 'unsupported', 'rejected', 'truncated']:
            server.scenario, server.operations = scenario, []
            result = subprocess.run([str(executable), str(fixture),
                                     f'ipp://127.0.0.1:{server.server_port}/ipp/print'], capture_output=True, text=True, timeout=60)
            if scenario == 'accepted':
                assert result.returncode == 0 and 'ACCEPTED 77 image/pwg-raster' in result.stdout, result.stdout + result.stderr
            else:
                assert result.returncode == 1, result.stdout
            assert server.operations == ([11] if scenario == 'unsupported' else [11, 2]), server.operations
            if scenario == 'truncated':
                assert 'avoid a duplicate' in result.stdout, result.stdout
            print(f'PASS {scenario}: {result.stdout.strip()}')
        subprocess.run(['clang', str(ROOT / 'tests/validate-pwg.c'), '-lcups', '-o', str(folder / 'validate-pwg')], check=True)
        subprocess.run([str(folder / 'validate-pwg'), str(server.raster)], check=True)
    finally:
        server.shutdown(); server.server_close()
