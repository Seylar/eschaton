"""Régression des écritures partielles et de la saturation, sans VM requise."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
import os
import pty
import select
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('vm_serial', str(Path(__file__).resolve().parents[1] / 'tools/vm-serial'))
spec = importlib.util.spec_from_loader(loader.name, loader)
serial = importlib.util.module_from_spec(spec)
loader.exec_module(serial)


class SerialWriteTests(unittest.TestCase):
    def test_partial_write_then_saturation_resumes_exactly(self):
        payload = bytes(range(150))
        sent = bytearray()
        limits = iter([3, None, 1, 64, 17, 64])

        def write(_fd, chunk):
            limit = next(limits, 64)
            if limit is None:
                raise BlockingIOError()
            count = min(len(chunk), limit)
            sent.extend(chunk[:count])
            return count

        offset = 0
        offsets = []
        with patch.object(serial.os, 'write', side_effect=write):
            while offset < len(payload):
                offset = serial.write_chunk(99, payload, offset)
                offsets.append(offset)
        self.assertEqual(offsets[:3], [3, 3, 4])
        self.assertEqual(sent, payload)

    def test_daemon_drains_echo_while_sending(self):
        master, slave = pty.openpty()
        process = None
        try:
            os.set_blocking(master, False)
            with tempfile.TemporaryDirectory() as folder:
                inbox = Path(folder) / 'inbox'
                inbox.mkdir()
                payload = b'0123456789abcdef' * 768
                (inbox / 'test.snd').write_bytes(payload)
                process = subprocess.Popen([sys.executable, loader.path, 'daemon',
                                            os.ttyname(slave), folder],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                received = bytearray()
                feedback = bytearray()
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    readable, writable, _ = select.select([master], [master] if feedback else [], [], 0.02)
                    if readable:
                        try:
                            chunk = os.read(master, 65536)
                        except BlockingIOError:
                            chunk = b''
                        received.extend(chunk)
                        feedback.extend(chunk)
                    if writable and feedback:
                        count = os.write(master, feedback)
                        del feedback[:count]
                    log = Path(folder) / 'console.log'
                    if ((inbox / 'test.sent').exists() and not feedback
                            and len(received) >= len(payload) and log.exists()
                            and log.read_bytes().endswith(payload)):
                        break
                self.assertEqual(received, payload)
                self.assertTrue((inbox / 'test.sent').exists())
                self.assertTrue(log.read_bytes().endswith(payload))
        finally:
            if process is not None:
                process.terminate()
                process.communicate(timeout=5)
            os.close(master)
            os.close(slave)

    def test_fatal_write_error_is_not_swallowed(self):
        with patch.object(serial.os, 'write', side_effect=OSError('disconnected')):
            with self.assertRaises(OSError):
                serial.write_chunk(99, b'command', 2)

    def test_zero_byte_write_keeps_pending_offset(self):
        with patch.object(serial.os, 'write', return_value=0):
            self.assertEqual(serial.write_chunk(99, b'command', 2), 2)


if __name__ == '__main__':
    unittest.main()
