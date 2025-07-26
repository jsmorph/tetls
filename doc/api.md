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

The `attestation` is an AWS Nitro attestation as described
[here](https://aws.amazon.com/blogs/compute/validating-attestation-documents-produced-by-aws-nitro-enclaves/).
See the [References](#references).

## Endpoints

### POST /tlsp: HTTPS requests

Proxy HTTPS requests with attestation.

(The name `tlsp` is an artifact and should be replaced.)

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
curl -X POST https://api.tetls.net/tlsp \
  -H "X-TEO-Authorization: your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://httpbin.org/get",
    "method": "GET",
    "headers": {"User-Agent": "TEO-Test"}
  }'
```

### GET /rng: Random Number Generation

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
curl -X GET https://api.tetls.net/rng \
  -H "X-TEO-Authorization: your-token"
```

### POST /js: JavaScript Execution

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
curl -X POST https://api.tetls.net/js \
  -H "X-TEO-Authorization: your-token" \
  -H "Content-Type: application/json" \
  -d '{"source": "return Math.random();"}'
```

## JavaScript Access To Native Functions

JavaScript can access the following functions:

1. `rng`: Get random bytes
1. `tlsp`: Make an HTTPS request
1. `attest`: Generate an attestation
1. `getidentity`: Get worker identity data
1. `addawssign`: Add AWS SigV4 signature to requests
1. `xmltojson`: Convert XML to JSON
1. `decrypt`: Decrypt using private key
1. `encrypt`: Encrypt using the public key (just for testing)

See below for details.

These functions can be called from JavaScript code executed via the `/js` endpoint by writing and reading JSON to the special `hpc` file:

```javascript
import * as std from 'std';

// Write request to hpc
const f = std.open("hpc", "w");
f.puts(JSON.stringify({function_name: parameters}));
f.close();

// Read response from hpc
const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();
```

For example, the following JavaScript function is handy:

```javascript
// Example arg: {"rng":{}}.
function hpc(arg) {
  const x = std.open('hpc', 'w');
  x.puts(JSON.stringify(arg));
  x.close();
  const y = std.open('hpc', 'r');
  const js = y.readAsString();
  print('// debug ' + js);
  return JSON.parse(js);
}

const random_byte = hpc({"rng":{}})['bytes'][0]; // See 'rng' below
```

"hpc" originally stood for "host procedure call", but the "host" in the case is the WASM engine, which is the "host" for the JavaScript interpreter. This "host" is _not_ the enclave's host!


### `rng`: Random Number Generation

Generates cryptographically secure random bytes using the AWS Nitro Enclave NSM.

**JavaScript Usage:**
```javascript
const result = hpc({"rng": {}});
const randomBytes = result.bytes;      // Array of random bytes
const randomHex = result.hex;          // Hex-encoded string
```

**Response:**
```json
{
  "bytes": [42, 156, 73, 91, ...],
  "hex": "2a9c495b..."
}
```

### `tlsp`: TLS Proxy

Performs an HTTPS request through the enclave's TLS proxy with attestation coverage.

**JavaScript Usage:**
```javascript
const result = hpc({
  "tlsp": {
    "url": "https://api.example.com/data",
    "method": "GET",
    "headers": {
      "User-Agent": "TEO-Worker/1.0",
      "Authorization": "Bearer token"
    },
    "body": "request-body-data"
  }
});

const responseStatus = result.status;
const responseBody = result.body;
const responseHeaders = result.headers;
```

**Response:**
```json
{
  "status": 200,
  "status_line": "HTTP/1.1 200 OK",
  "headers": {
    "content-type": "application/json",
    "content-length": "42"
  },
  "body": "response-body-data"
}
```

**Security Notes:**
- All proxy requests are covered by the enclave's attestation
- Authorization headers are automatically redacted with HMAC-SHA256 in attestation logs
- X-TEO-Authorization headers are automatically removed from proxied requests

### `attest`:  Generate Attestation

Creates a cryptographic attestation document covering the provided data using the AWS Nitro Enclave NSM.

**JavaScript Usage:**
```javascript
const result = hpc({
  "attest": {
    "data": "Data to be attested"
  }
});
const attestationHex = result.hex;
```

**Response:**
```json
{
  "hex": "846a5369676e6174757265..."
}
```

**Security Note:** The attestation document cryptographically proves that the specified data was processed within this specific enclave instance.

### `getidentity`: Get Worker Identity Information

Retrieves the worker's identity data including the public key, source code hash, and attestation. This function returns the cryptographic identity established when the worker was initialized.  This triple effectively uniquely identifies the execution of this JavaScript source in the enclave.

This data could be given to an endpoint (via `tlsp`) to obtain credentials that are subsequently used for other operations. That endpoint should encrypt the credentials for the public key given in the request, and the JavaScript can `decrypt` that ciphertext.  This approach should be secure (assuming the enclave and its image are) because the endpoint can authenticate the requester, and the private key in the enclave is not accessible outside that runtime (even to the JavaScript that's executing).

**JavaScript Usage:**
```javascript
import * as std from 'std';

const f = std.open("hpc", "w");
f.puts(JSON.stringify({"getidentity": {}}));
f.close();

const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();

const publicKey = result.public_key;
const sourceHash = result.source_hash;
const attestation = result.attestation;
```

**Response:**
```json
{
  "public_key": "04abcd1234567890abcdef...",
  "source_hash": "sha256hash1234567890abcdef...",
  "attestation": "846a5369676e6174757265..."
}
```

**Response Fields:**
- `public_key`: Hex-encoded public key from the worker's key pair
- `source_hash`: SHA-256 hash of the source code used to initialize the worker
- `attestation`: Hex-encoded attestation document covering `hash(public_key, source_hash)`

**Security Notes:**
- The source hash cryptographically binds the worker's identity to its source code
- The attestation proves that the identity was established within this specific enclave instance
- If the worker was not initialized with source code (missing `-e` flag), all fields will be empty strings

### `addawssign`: Add AWS SigV4 Signature

Adds AWS Signature Version 4 authentication to HTTP requests. This function takes a request object and AWS credentials, then returns the same request with the proper AWS authentication headers added.

**JavaScript Usage:**
```javascript
import * as std from 'std';

const f = std.open("hpc", "w");
f.puts(JSON.stringify({
  "addawssign": {
    "request": {
      "url": "https://s3.amazonaws.com/my-bucket/my-object",
      "method": "GET",
      "headers": {
        "Host": "s3.amazonaws.com"
      },
      "body": null
    },
    "credentials": {
      "access_key": "AKIAIOSFODNN7EXAMPLE",
      "secret_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      "region": "us-east-1", 
      "service": "s3"
    }
  }
}));
f.close();

const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();

const signedRequest = result.signed_request;
```

**Request Fields:**
- `request`: HTTP request object to be signed
  - `url`: The target URL
  - `method`: HTTP method (GET, POST, etc.)
  - `headers`: Request headers object (optional)
  - `body`: Request body string (optional)
- `credentials`: AWS credentials object
  - `access_key`: AWS access key ID
  - `secret_key`: AWS secret access key
  - `region`: AWS region (e.g., "us-east-1")
  - `service`: AWS service name (e.g., "s3", "lambda")

**Response:**
```json
{
  "signed_request": {
    "url": "https://s3.amazonaws.com/my-bucket/my-object",
    "method": "GET", 
    "headers": {
      "Host": "s3.amazonaws.com",
      "authorization": "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20250726/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=fb594df9535686e66d0970e5cc52352fd381a028d395564db01ffe9c24c6ca01",
      "x-amz-date": "20250726T133944Z",
      "X-Amz-Content-Sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    },
    "body": null
  }
}
```

**Security Notes:**
- AWS credentials are never stored or logged by the worker
- All signing operations use the official AWS SigV4 algorithm
- Signatures include timestamp and content hash for integrity
- The signed request can be used immediately with AWS services

### `xmltojson`: XML to JSON Conversion

Converts XML strings to JSON format. This function is particularly useful for processing AWS API responses, which are typically returned in XML format.

**JavaScript Usage:**
```javascript
import * as std from 'std';

const f = std.open("hpc", "w");
f.puts(JSON.stringify({
  "xmltojson": {
    "xml": "<ListBucketsResult><Buckets><Bucket><Name>my-bucket</Name></Bucket></Buckets></ListBucketsResult>"
  }
}));
f.close();

const f2 = std.open("hpc", "r");
const result = JSON.parse(f2.readAsString());
f2.close();

const jsonData = JSON.parse(result.json);
```

**Request Fields:**
- `xml`: XML string to be converted to JSON

**Response:**
```json
{
  "json": "{\"ListBucketsResult\":{\"Buckets\":{\"Bucket\":{\"Name\":\"my-bucket\"}}}}"
}
```

**Error Response:**
```json
{
  "error": "Failed to parse XML: unexpected end of input"
}
```

**Usage Notes:**
- The function returns a JSON object containing a `json` field with the converted XML as a JSON string
- On parsing errors, returns a JSON object with an `error` field containing the error message
- Supports complex XML structures including nested elements and attributes
- Designed to work well with AWS API responses

### `encrypt`: Public Key Encryption

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

### `decrypt`: Private Key Decryption

Decrypts ECIES ciphertext using the private key established when the worker was initialized.

Typically some endpoint encrypted data, requested by `tlsp` with `getidentity` data, based on the public key in that identity data. Then the client can `decrypt` that ciphertext.  Note that the private key is not itself accessible from JavaScript.

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

### Cryptographic Details

- **Elliptic Curve**: NIST P-256 (secp256r1)
- **Key Agreement**: ECDH (Elliptic Curve Diffie-Hellman)
- **Key Derivation**: HKDF with SHA-256
- **Symmetric Encryption**: AES-256-GCM
- **Random Generation**: AWS Nitro Enclave NSM (cryptographically secure)
- **Perfect Forward Secrecy**: Each encryption uses a fresh ephemeral key pair

### Security Notes

1. **Private Key Storage**: Private keys are established at worker initialization and stored securely in memory, never exposed to JavaScript
2. **Attestation Coverage**: All cryptographic operations are covered by the enclave's attestation
3. **Randomness**: All random values (private keys, nonces) come from the NSM hardware RNG
4. **Authentication**: AES-GCM provides built-in authentication preventing tampering
5. **Identity Binding**: Worker identity is cryptographically bound to the source code through attestation

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
