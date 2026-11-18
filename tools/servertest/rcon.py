"""最小的 Source RCON 客戶端（只用標準函式庫）。

協定：https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
"""
import socket
import struct

SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


class RconError(Exception):
    pass


class Rcon:
    def __init__(self, host, port, password, timeout=5.0):
        self.sock = socket.create_connection((host, port), timeout)
        self.sock.settimeout(timeout)
        self._id = 0
        self._send(SERVERDATA_AUTH, password)
        # srcds 會先回一個空的 RESPONSE_VALUE，再回 AUTH_RESPONSE
        while True:
            rid, typ, _ = self._recv()
            if typ == SERVERDATA_AUTH_RESPONSE:
                if rid == -1:
                    raise RconError("RCON 密碼錯誤")
                break

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def _send(self, typ, body):
        self._id += 1
        data = struct.pack("<ii", self._id, typ) + body.encode("utf-8") + b"\x00\x00"
        self.sock.sendall(struct.pack("<i", len(data)) + data)
        return self._id

    def _recvn(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise RconError("連線被伺服器關閉")
            buf += chunk
        return buf

    def _recv(self):
        size = struct.unpack("<i", self._recvn(4))[0]
        data = self._recvn(size)
        rid, typ = struct.unpack("<ii", data[:8])
        body = data[8:-2].decode("utf-8", "replace")
        return rid, typ, body

    def cmd(self, command, first_timeout=10.0, idle_timeout=0.8):
        """送出指令並收集輸出。

        srcds 會把長輸出拆成多個封包。送完指令後再送一個空的 RESPONSE_VALUE 當結束標記，
        收到標記的回應就代表輸出結束；部分遊戲不回應標記，所以也用閒置逾時當作結束。
        """
        cid = self._send(SERVERDATA_EXECCOMMAND, command)
        mid = self._send(SERVERDATA_RESPONSE_VALUE, "")
        out = []
        self.sock.settimeout(first_timeout)
        try:
            while True:
                rid, _, body = self._recv()
                if rid == mid:
                    break
                if rid == cid:
                    out.append(body)
                self.sock.settimeout(idle_timeout)
        except socket.timeout:
            pass
        return "".join(out)
