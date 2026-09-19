import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import exporter


class FakeOllamaHandler(BaseHTTPRequestHandler):
    models = [
        {"name": "qwen2.5:0.5b", "size": 397821319, "digest": "a" * 64},
        {"name": "qwen2.5:1.5b", "size": 986062023, "digest": "b" * 64},
    ]

    def do_GET(self):
        if self.path == "/":
            body = b"Ollama is running"
        elif self.path == "/api/tags":
            body = json.dumps({"models": self.models}).encode()
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def start_fake_ollama():
    server = HTTPServer(("127.0.0.1", 0), FakeOllamaHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, "http://127.0.0.1:%d" % server.server_address[1]


def start_exporter_server():
    server = HTTPServer(("127.0.0.1", 0), exporter.MetricsHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, "http://127.0.0.1:%d" % server.server_address[1]


def reset_metrics():
    exporter.metrics.update({
        "ollama_up": 0,
        "ollama_api_response_time_seconds": 0,
        "ollama_models_loaded": 0,
        "ollama_models_list": [],
        "ollama_api_latency_seconds_bucket": {},
        "ollama_scrape_errors_total": 0,
    })


class ScrapeMetricsTest(unittest.TestCase):
    def setUp(self):
        reset_metrics()
        self._original_url = exporter.OLLAMA_URL

    def tearDown(self):
        exporter.OLLAMA_URL = self._original_url
        reset_metrics()

    def test_scrape_once_marks_ollama_up_and_counts_models(self):
        server, url = start_fake_ollama()
        try:
            exporter.OLLAMA_URL = url
            exporter.scrape_once()
        finally:
            server.shutdown()

        self.assertEqual(exporter.metrics["ollama_up"], 1)
        self.assertEqual(exporter.metrics["ollama_models_loaded"], 2)
        self.assertEqual(
            [m["name"] for m in exporter.metrics["ollama_models_list"]],
            ["qwen2.5:0.5b", "qwen2.5:1.5b"],
        )

    def test_scrape_once_truncates_digest_to_sixteen_chars(self):
        server, url = start_fake_ollama()
        try:
            exporter.OLLAMA_URL = url
            exporter.scrape_once()
        finally:
            server.shutdown()

        digests = [m["digest"] for m in exporter.metrics["ollama_models_list"]]
        self.assertEqual(digests, ["a" * 16, "b" * 16])

    def test_scrape_once_marks_down_and_counts_error_when_unreachable(self):
        exporter.OLLAMA_URL = "http://127.0.0.1:1"
        before = exporter.metrics["ollama_scrape_errors_total"]

        exporter.scrape_once()

        self.assertEqual(exporter.metrics["ollama_up"], 0)
        self.assertEqual(exporter.metrics["ollama_scrape_errors_total"], before + 1)

    def test_scrape_once_zeroes_latency_when_unreachable(self):
        exporter.OLLAMA_URL = "http://127.0.0.1:1"
        exporter.metrics["ollama_api_response_time_seconds"] = 1.234

        exporter.scrape_once()

        self.assertEqual(exporter.metrics["ollama_api_response_time_seconds"], 0)

    def test_scrape_once_keeps_serving_last_known_models_when_ollama_gone(self):
        server, url = start_fake_ollama()
        try:
            exporter.OLLAMA_URL = url
            exporter.scrape_once()
        finally:
            server.shutdown()
        loaded = exporter.metrics["ollama_models_loaded"]

        exporter.OLLAMA_URL = "http://127.0.0.1:1"
        exporter.scrape_once()

        self.assertEqual(exporter.metrics["ollama_models_loaded"], loaded)
        self.assertEqual(exporter.metrics["ollama_up"], 0)


class MetricsEndpointTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server, cls.base = start_exporter_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        reset_metrics()

    def fetch(self, path):
        with urllib.request.urlopen(self.base + path, timeout=10) as resp:
            return resp.status, dict(resp.headers), resp.read().decode()

    def test_metrics_endpoint_returns_prometheus_text_format(self):
        status, headers, body = self.fetch("/metrics")

        self.assertEqual(status, 200)
        self.assertIn("text/plain", headers["Content-Type"])
        self.assertTrue(body.endswith("\n"))

    def test_metrics_endpoint_declares_all_six_families(self):
        _, _, body = self.fetch("/metrics")

        for family in (
            "ollama_up",
            "ollama_api_response_time_seconds",
            "ollama_models_loaded",
            "ollama_model_info",
            "sre_lab_build_info",
            "ollama_scrape_errors_total",
        ):
            with self.subTest(family=family):
                self.assertIn("# TYPE %s " % family, body)

    def test_every_metric_family_has_exactly_one_type_declaration(self):
        _, _, body = self.fetch("/metrics")
        declared = [l.split()[2] for l in body.splitlines() if l.startswith("# TYPE ")]

        self.assertEqual(len(declared), len(set(declared)))

    def test_every_metric_line_is_parsable(self):
        _, _, body = self.fetch("/metrics")
        samples = [l for l in body.splitlines() if l and not l.startswith("#")]

        self.assertTrue(samples)
        for line in samples:
            with self.subTest(line=line):
                name_and_labels, _, value = line.rpartition(" ")
                self.assertTrue(name_and_labels)
                float(value)

    def test_build_info_exposes_revision_label(self):
        original = exporter.BUILD_REVISION
        exporter.BUILD_REVISION = "deadbee"
        try:
            _, _, body = self.fetch("/metrics")
        finally:
            exporter.BUILD_REVISION = original

        self.assertIn('sre_lab_build_info{revision="deadbee"} 1', body)

    def test_model_info_line_emitted_for_each_loaded_model(self):
        exporter.metrics["ollama_models_list"] = [
            {"name": "qwen2.5:0.5b", "size": 397821319, "digest": "a" * 16},
            {"name": "llama3.2:3b", "size": 2019393189, "digest": "c" * 16},
        ]

        _, _, body = self.fetch("/metrics")

        self.assertIn('ollama_model_info{model="qwen2.5:0.5b",digest="%s"} 397821319' % ("a" * 16), body)
        self.assertIn('ollama_model_info{model="llama3.2:3b",digest="%s"} 2019393189' % ("c" * 16), body)

    def test_model_info_metric_has_no_sample_when_no_models_loaded(self):
        exporter.metrics["ollama_models_list"] = []

        _, _, body = self.fetch("/metrics")
        samples = [l for l in body.splitlines() if l.startswith("ollama_model_info{")]

        self.assertEqual(samples, [])

    def test_health_endpoint_returns_ok(self):
        status, headers, body = self.fetch("/health")

        self.assertEqual(status, 200)
        self.assertIn("application/json", headers["Content-Type"])
        self.assertEqual(json.loads(body), {"status": "ok"})

    def test_unknown_path_returns_404(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self.fetch("/nope")

        self.assertEqual(ctx.exception.code, 404)


if __name__ == "__main__":
    unittest.main(verbosity=2)
