import ssl
import socket
import hashlib
import base64
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

def get_pins(hostname):
    ctx = ssl.create_default_context()
    with socket.create_connection((hostname, 443)) as sock:
        with ctx.wrap_socket(sock, server_hostname=hostname) as ssock:
            # We want the whole chain, but getpeercert only gives the leaf.
            # Python standard library doesn't easily expose the full chain sent by the server.
            # We can just use openssl.
            pass

print("Use openssl to get the chain")
