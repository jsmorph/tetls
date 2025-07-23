# API

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
