import sys, base64, hashlib
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

data = open("chain.pem", "r").read()
certs = data.split("-----BEGIN CERTIFICATE-----")[1:]
for c in certs:
    try:
        end_idx = c.find("-----END CERTIFICATE-----")
        if end_idx == -1: continue
        pem = "-----BEGIN CERTIFICATE-----" + c[:end_idx] + "-----END CERTIFICATE-----\n"
        cert = x509.load_pem_x509_certificate(pem.encode(), default_backend())
        pub_der = cert.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
        pin = base64.b64encode(hashlib.sha256(pub_der).digest()).decode()
        print("Subject:", cert.subject)
        print("Pin:", pin)
    except Exception as e:
        print("Error parsing cert", e)
