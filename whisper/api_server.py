import http.server
import socketserver
import os
import subprocess
import traceback

PORT = 5001
UPLOAD_DIR = "/app/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

class WhisperHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/transcribe":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        print("Received valid POST request at /transcribe")
        content_length = int(self.headers['Content-Length'])
        content_type = self.headers.get('Content-Type', '')
        if 'multipart/form-data' not in content_type:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Expected multipart/form-data")
            return

        # Parse multipart form data (very basic, not robust for production)
        boundary = content_type.split("boundary=")[-1].encode()
        body = self.rfile.read(content_length)
        parts = body.split(b"--" + boundary)
        for part in parts:
            if b'Content-Disposition' in part and b'filename="' in part:
                header, filedata = part.split(b"\r\n\r\n", 1)
                filename = header.split(b'filename="')[1].split(b'"')[0].decode()
                filepath = os.path.join(UPLOAD_DIR, filename)
                with open(filepath, "wb") as f:
                    f.write(filedata.rstrip(b"\r\n--"))
                print(f"Saved file to {filepath}")
                # Run whisper CLI
                print(f"Starting Whisper CLI for {filepath}")
                result = subprocess.run(
                    [
                        "whisper", filepath,
                        "--model", "small",
                        "--output_format", "json",
                        "--output_dir", UPLOAD_DIR
                    ],
                    capture_output=True, text=True
                )
                # Read the output transcript as JSON
                transcript_file = filepath.rsplit(".", 1)[0] + ".json"
                try:
                    if os.path.exists(transcript_file):
                        with open(transcript_file, "r") as tf:
                            transcript_json = tf.read()
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(transcript_json.encode())
                    else:
                        self.send_response(500)
                        self.end_headers()
                        error_message = (
                            f"Whisper CLI failed.\n"
                            f"Return code: {result.returncode}\n"
                            f"stdout: {result.stdout}\n"
                            f"stderr: {result.stderr}\n"
                        )
                        print(error_message)
                        self.wfile.write(error_message.encode())
                except Exception as e:
                    self.send_response(500)
                    self.end_headers()
                    tb = traceback.format_exc()
                    print(tb)
                    self.wfile.write(tb.encode())
                return

        self.send_response(400)
        self.end_headers()
        self.wfile.write(b"No file found in request")

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), WhisperHandler) as httpd:
        print(f"Serving on port {PORT}")
        httpd.serve_forever()
