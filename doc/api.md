# API

## Examples

See [these examples](../examples).

## Authentication

All requests require the `X-TEO-Authorization` header:

```
X-TEO-Authorization: <token>
```

Missing or invalid tokens return `401 Unauthorized`.

## Response Format

All successful responses return an attestation object:

```json
{
  "data": {
    "request": "<base64-encoded-request>",
    "response": "<base64-encoded-response>",
    "request_headers": "<base64-encoded-headers>",
    "response_headers": "<base64-encoded-headers>",
    "response_status_line": "<base64-encoded-status>",
    "error": null
  },
  "attestation": "<base64-attestation-document>",
  "hash": "<sha256-hash>",
  "parsed_response_body": <parsed-json-response>
}
```

The attestation is an AWS Nitro attestation as described
[here](https://aws.amazon.com/blogs/compute/validating-attestation-documents-produced-by-aws-nitro-enclaves/).
See the [References](#references).

## Endpoints

### POST /js - JavaScript Execution

Execute JavaScript code in a WASM environment.

**Request Body:**
```json
{
  "source": "console.log('Hello World'); return {result: 42};",
  "arg": "optional-argument"
}
```

**Source Field Options:**
- String: Single line or multiline JavaScript code
- Array: Array of strings joined with newlines

**Response Body (in attestation data.response):**
```json
{
  "result": "<execution-result-string>",
  "error": null,
  "parsed_response": <parsed-json-if-valid>
}
```

**Example:**
```bash
curl -X POST https://enclave:5002/js \
  -H "X-TEO-Authorization: your-token" \
  -H "Content-Type: application/json" \
  -d '{"source": "return Math.random();"}'
```

### GET /rng - Random Number Generation

Generate cryptographically secure random bytes.

**Response Body (in attestation data.response):**
```json
{
  "bytes": [1, 2, 3, ...],
  "hex": "0102030405..."
}
```

**Example:**
```bash
curl -X GET https://enclave:5002/rng \
  -H "X-TEO-Authorization: your-token"
```

### POST /tlsp - TLS Proxy

Proxy HTTPS requests with attestation.

**Request Body:**
```json
{
  "url": "https://api.example.com/data",
  "method": "GET",
  "headers": {
    "User-Agent": "TEO-Worker/1.0",
    "Authorization": "Bearer token"
  },
  "body": "request-body-data"
}
```

**Response Body (in attestation data.response):**
```json
{
  "status": 200,
  "status_line": "HTTP/1.1 200 OK",
  "headers": {
    "content-type": "application/json"
  },
  "body": "response-body-data"
}
```

**Security Notes:**
- Authorization headers are redacted with HMAC-SHA256
- X-TEO-Authorization headers are automatically removed

**Example:**
```bash
curl -X POST https://enclave:5002/tlsp \
  -H "X-TEO-Authorization: your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://httpbin.org/get",
    "method": "GET",
    "headers": {"User-Agent": "TEO-Test"}
  }'
```

## JavaScript Handler Functions

The following functions can be called from JavaScript code executed via the `/js` endpoint by writing JSON to the `hpc` file:

```javascript
import * as std from 'std';

// Write request to hpc file
const f = std.open("hpc", "w");
f.puts(JSON.stringify({function_name: parameters}));
f.close();

// Read response from hpc file
const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();
```

For example, the following JavaScript function is handy:

```javascript
# Example arg: {"rng":{}}.
function hpc(arg) {
  const x = std.open('hpc', 'w');
  x.puts(JSON.stringify(arg));
  x.close();
  const y = std.open('hpc', 'r');
  const js = y.readAsString();
  print('// debug ' + js);
  return JSON.parse(js);
}
```


### `genkeypair` - Generate Elliptic Curve Key Pair

Generates a P-256 elliptic curve key pair for ECIES encryption. The private key is stored securely in memory for the duration of the JavaScript execution.

**JavaScript Usage:**
```javascript
import * as std from 'std';

const f = std.open("hpc", "w");
f.puts(JSON.stringify({"genkeypair": {}}));
f.close();

const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();

const publicKey = result.public_key;
```

**Response:**
```json
{
  "public_key": "04abcd1234567890abcdef..." 
}
```

### `encrypt` - Public Key Encryption

Encrypts plaintext using ECIES (Elliptic Curve Integrated Encryption Scheme) with AES-256-GCM and HKDF key derivation.

**JavaScript Usage:**
```javascript
const f = std.open("hpc", "w");
f.puts(JSON.stringify({
  "encrypt": {
    "public_key": "04abcd1234567890abcdef...",
    "plaintext": "Hello, secure world!"
  }
}));
f.close();

const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();

const ciphertext = result.ciphertext;
```

**Response:**
```json
{
  "ciphertext": "deadbeef1234567890abcdef..."
}
```

### `decrypt` - Private Key Decryption

Decrypts ECIES ciphertext using the private key from the most recent `genkeypair` call in the same JavaScript execution session.

**JavaScript Usage:**
```javascript
const f = std.open("hpc", "w");
f.puts(JSON.stringify({
  "decrypt": {
    "ciphertext": "deadbeef1234567890abcdef..."
  }
}));
f.close();

const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();

const plaintext = result.plaintext;
```

**Response:**
```json
{
  "plaintext": "Hello, secure world!"
}
```

### Complete Example: End-to-End Encryption

```javascript
import * as std from 'std';

// Generate key pair
let f = std.open("hpc", "w");
f.puts(JSON.stringify({"genkeypair": {}}));
f.close();
f = std.open("hpc", "r");
const keyResult = JSON.parse(f.readAsString());
f.close();

const publicKey = keyResult.public_key;

// Encrypt data
f = std.open("hpc", "w");
f.puts(JSON.stringify({
  "encrypt": {
    "public_key": publicKey,
    "plaintext": "Secret message"
  }
}));
f.close();
f = std.open("hpc", "r");
const encryptResult = JSON.parse(f.readAsString());
f.close();

const ciphertext = encryptResult.ciphertext;

// Decrypt data
f = std.open("hpc", "w");
f.puts(JSON.stringify({
  "decrypt": {
    "ciphertext": ciphertext
  }
}));
f.close();
f = std.open("hpc", "r");
const decryptResult = JSON.parse(f.readAsString());
f.close();

print(decryptResult.plaintext); // "Secret message"
```

### Cryptographic Details

- **Elliptic Curve**: NIST P-256 (secp256r1)
- **Key Agreement**: ECDH (Elliptic Curve Diffie-Hellman)
- **Key Derivation**: HKDF with SHA-256
- **Symmetric Encryption**: AES-256-GCM
- **Random Generation**: AWS Nitro Enclave NSM (cryptographically secure)
- **Perfect Forward Secrecy**: Each encryption uses a fresh ephemeral key pair

### Security Notes

1. **Private Key Storage**: Private keys are stored in memory only during JavaScript execution and are never exposed
2. **Attestation Coverage**: All cryptographic operations are covered by the enclave's attestation
3. **Randomness**: All random values (private keys, nonces) come from the NSM hardware RNG
4. **Authentication**: AES-GCM provides built-in authentication preventing tampering
5. **Key Isolation**: Each `genkeypair` call generates a fresh key pair independent of previous calls

## Error Responses

### 401 Unauthorized
```json
{"error": "Unauthorized"}
```

### 404 Not Found
```json
{"error": "Not found"}
```

### 400 Bad Request
- Missing request body
- Invalid JSON format
- Missing required fields

### 502 Bad Gateway
- Proxy request failures

## Security Features

1. **Attestation**: All responses include cryptographic attestation documents
2. **Header Redaction**: Authorization headers replaced with HMAC-SHA256 hashes
3. **Request Limits**: Maximum request size enforced
4. **TLS Termination**: All connections require valid TLS
5. **Token Validation**: Authorization tokens verified against auxiliary service

## Technical Details

- **VSOCK Communication**: Uses Linux VSOCK for enclave isolation
- **TLS Configuration**: Auto-generated or fetched certificates
- **Threading**: Each connection handled in separate thread
- **Attestation Hash**: SHA256 of request-response pair with redacted sensitive data

# References

1. ["Validating attestation documents produced by AWS Nitro
   Enclaves"](https://aws.amazon.com/blogs/compute/validating-attestation-documents-produced-by-aws-nitro-enclaves/)
1. ["Nitro Enclaves Attestation
   Process"](https://github.com/aws/aws-nitro-enclaves-nsm-api/blob/main/docs/attestation_process.md)
1. ["Verifying the root of
   trust"](https://docs.aws.amazon.com/enclaves/latest/user/verify-root.html)
1. [Examples](../examples)
