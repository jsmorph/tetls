if [ -z "$TEO_AUTH" ]; then
    echo "Need TEO_AUTH"; exit 1
fi

echo '# Get cryptographic random bytes'
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST https://api.tetls.net/rng | 
    tee test.json |
    jq -c .parsed_response_body.bytes | jq .

cat test.json | jq . 
echo

echo '# Get the "current" time from someone on the Internet'
curl -s -H "X-TEO-Authorization: $TEO_AUTH" \
     -X POST https://api.tetls.net/tlsp \
     -d '{
        "url": "https://postman-echo.com/time/now",
        "method": "GET",
        "headers": {
          "Content-Type": "application/json"
        }}' |
    tee test.json |
    jq -r .parsed_response_body.body

cat test.json | jq . 
echo

echo "# Javascript 'eval' is available"
cat<<EOF > d.json
{"source": ["const code = '1+2';", 
            "const result = eval(code);",
            "print(JSON.stringify(result));"
           ]
}
EOF
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST  -d @d.json https://api.tetls.net/js | 
    tee test.json |
    jq -r .parsed_response_body.body | jq .

cat test.json | jq . 
echo

echo '# Flip a coin ("heads" or "tails") with cryptographic randomness'
cat<<EOF > d.json
{"arg": ["heads","tails"],
"source": ["import * as std from 'std';",
           "const coin = JSON.parse(std.getenv('TEO_JAVASCRIPT_ARG')); // Access to arguments above ",
           "const x = std.open('hpc', 'w'); // Magic filename for API ",
           "x.puts(JSON.stringify({'rng':{}})); // Send our API request ",
           "x.close();",
           "const y = std.open('hpc', 'r');",
           "const str = y.readAsString();",
           "const z = JSON.parse(str);",
           "const n = z['bytes'][0];",
		   "print('// n: ' + n);",
           "const i = n % 2;",
		   "print('// i: ' + i);",
           "print(JSON.stringify({'flip':coin[i]}));"
          ]
}
EOF
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST  -d @d.json https://api.tetls.net/js | 
    tee test.json |
    jq -r .parsed_response_body.body | jq .

cat test.json | jq . 
echo

echo '# Get an LLM response from OpenAI'
curl -s -X POST \
     -H "X-TEO-Authorization: $TEO_AUTH" \
     -H "Content-Type: application/json" \
     -d '{
          "url": "https://api.openai.com/v1/responses",
          "method": "POST",
          "headers": {
             "Content-Type": "application/json",
             "Authorization": "Bearer '$OPENAI_API_KEY'"
           },
         "body": "{\"input\":[{\"role\":\"system\",\"content\":\"You are a helpful and polite assistant.\"},{\"role\":\"user\",\"content\":\"Give me an exotic taco receipe along with a cocktail recommendation.\"}],\"model\":\"gpt-4\",\"stream\":false,\"max_output_tokens\":120}"
  }' https://api.tetls.net/tlsp  |
    tee test.json |
    jq -r .parsed_response_body.body | jq .


cat test.json | jq . 
echo

echo '# Get an attestation from Javascript'
cat<<EOF > d.json
{"source": ["import * as std from 'std';",
           "const x = std.open('hpc', 'w');",
           "x.puts(JSON.stringify({attest:{data:'Tacos are good.'}}));",
           "x.close();",
           "const y = std.open('hpc', 'r');",
           "const js = y.readAsString();",
           "const a = JSON.parse(js);",
           "const result = {attestation: a};",
           "print(JSON.stringify(result));"
          ]
}
EOF
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST  -d @d.json https://api.tetls.net/js | 
    tee test.json | jq .
echo

echo '# Get my identity'
cat<<EOF > d.json
{"source": ["import * as std from 'std';",
            "function hpc(arg) {",
            "  const x = std.open('hpc', 'w');",
            "  x.puts(JSON.stringify(arg));",
            "  x.close();",
            "  const y = std.open('hpc', 'r');",
            "  const js = y.readAsString();",
            "  return JSON.parse(js);",
            "}",
            "print(JSON.stringify(hpc({getidentity:{}})));"
          ]
}
EOF
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST  -d @d.json https://api.tetls.net/js | 
    tee test.json |
    jq -r .parsed_response_body
echo


echo '# Exercise the public key functions'
cat<<EOF > d.json
{"source": ["import * as std from 'std';",
            "function hpc(arg) {",
            "  const x = std.open('hpc', 'w');",
            "  x.puts(JSON.stringify(arg));",
            "  x.close();",
            "  const y = std.open('hpc', 'r');",
            "  const js = y.readAsString();",
            "  return JSON.parse(js);",
            "}",

            "const plaintext = 'tacos';",
	    "const pubkey = hpc({'getidentity':{}})['public_key'];",
	    "const co = hpc({'encrypt':{'public_key':pubkey,'plaintext':plaintext}});",
	    "const ciphertext = co['ciphertext'];",
	    "const check = hpc({'decrypt':{'ciphertext':ciphertext}})['plaintext'];",
            "const result = {public_key: pubkey, plaintext: plaintext, ciphertext: ciphertext, check: check};",
            "print(JSON.stringify(result));"
          ]
}
EOF
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST  -d @d.json https://api.tetls.net/js | 
    tee test.json |
    jq -r .parsed_response_body
echo

echo '# AWS-sign an HTTP request'
cat<<EOF > d.json
{"source": ["import * as std from 'std';",
            "function hpc(arg) {",
            "  const x = std.open('hpc', 'w');",
            "  x.puts(JSON.stringify(arg));",
            "  x.close();",
            "  const y = std.open('hpc', 'r');",
            "  const js = y.readAsString();",
            "  return JSON.parse(js);",
            "}",
	    "const arg = {",
	    "  'addawssign': {",
	    "    'request': {",
	    "      'url': 'https://s3.amazonaws.com/my-bucket/my-object',",
	    "      'method': 'GET',",
	    "      'headers': {",
	    "        'Host': 's3.amazonaws.com'",
	    "      },",
	    "      'body': null",
	    "    },",
	    "    'credentials': {",
	    "      'access_key': 'AKIAIOSFODNN7EXAMPLE',",
	    "      'secret_key': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',",
	    "      'region': 'us-east-1', ",
	    "      'service': 's3'",
	    "    }",
	    "  }",
	    "}",
            "print(JSON.stringify(hpc(arg)));"
          ]
}
EOF
curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST  -d @d.json https://api.tetls.net/js | 
    tee test.json |
    jq -r .parsed_response_body
echo

echo '# AWS API request'
cat<<EOF > d.json
{"source": [
    "import * as std from 'std';",
    "",
    "// Helper function to call native functions via hpc",
    "function hpc(arg) {",
    "    const f = std.open('hpc', 'w');",
    "    f.puts(JSON.stringify(arg));",
    "    f.close();",
    "    const f2 = std.open('hpc', 'r');",
    "    const result = JSON.parse(f2.readAsString());",
    "    f2.close();",
    "    return result;",
    "}",
    "",
    "// AWS credentials - replace actual credentials the program might get from another endpoint.",
    "// For example, make an HTTP request that provides results from getidentity in order to obtain these crendentials.",
    "const AWS_CREDENTIALS = {",
    "    access_key: '$TEST_AWS_ACCESS_KEY',",
    "    secret_key: '$TEST_AWS_SECRET_ACCESS_KEY',",
    "    region: 'us-east-1',",
    "    service: 's3'",
    "};",
    "",
    "// Create the S3 ListBuckets request",
    "const s3Request = {",
    "    url: 'https://s3.amazonaws.com/',",
    "    method: 'GET',",
    "    headers: {",
    "        'Host': 's3.amazonaws.com'",
    "    },",
    "    body: null",
    "};",
    "",
    "try {",
    "    // Initialize bucket names array",
    "    let bucketNames = [];",
    "    const signResult = hpc({",
    "        'addawssign': {",
    "            'request': s3Request,",
    "            'credentials': AWS_CREDENTIALS",
    "        }",
    "    });",
    "    const signedRequest = signResult.signed_request;",
    "    const response = hpc({",
    "        'tlsp': signedRequest",
    "    });",
    "    if (response.status === 200) {",
    "        print('// S3 ListBuckets request successful');",
    "        print('// Response status: ' + response.status);",
    "        // Parse the XML response to extract bucket names",
    "        const responseBody = response.body;",
    "        ",
    "        // Convert XML to JSON",
    "        const xmlResult = hpc({",
    "            'xmltojson': {",
    "                'xml': responseBody",
    "            }",
    "        });",
    "        if (xmlResult.error) {",
    "            print('// Failed to parse XML: ' + xmlResult.error);",
    "        } else {",
    "            // Parse the JSON string",
    "            const parsedXml = JSON.parse(xmlResult.json);",
    "            print('// Parsed XML as JSON');",
    "            ",
    "            // Extract bucket names if available",
    "            if (parsedXml.ListAllMyBucketsResult && parsedXml.ListAllMyBucketsResult.Buckets) {",
    "                const buckets = parsedXml.ListAllMyBucketsResult.Buckets;",
    "                if (buckets.Bucket) {",
    "                    // Handle both single bucket and multiple buckets",
    "                    const bucketList = Array.isArray(buckets.Bucket) ? buckets.Bucket : [buckets.Bucket];",
    "                    print('// Found ' + bucketList.length + ' bucket(s):');",
    "                    ",
    "                    for (let i = 0; i < bucketList.length; i++) {",
    "                        const bucket = bucketList[i];",
    "                        bucketNames.push(bucket.Name);",
    "                    }",
    "                } else {",
    "                    print('// No buckets found in the account');",
    "                }",
    "            } else {",
    "                print('// Unexpected XML structure - could not find bucket information');",
    "            }",
    "        }",
    "        ",
    "    } else {",
    "        print('// S3 request failed');",
    "        print('// Status: ' + response.status);",
    "        print('// Status line: ' + response.status_line);",
    "        print('// Response body: ' + response.body);",
    "        ",
    "        // Check for common AWS errors",
    "        if (response.status === 403) {",
    "            print('// ');",
    "            print('// This might be due to:');",
    "            print('// - Invalid AWS credentials');",
    "            print('// - Insufficient IAM permissions (need s3:ListAllMyBuckets)');",
    "            print('// - Incorrect signature calculation');",
    "        } else if (response.status === 400) {",
    "            print('// ');",
    "            print('// This might be due to:');",
    "            print('// - Malformed request');",
    "            print('// - Invalid signature format');",
    "            print('// - Clock skew (check system time)');",
    "        }",
    "    }",
    "    ",
    "    // Return success indicator with bucket names",
    "    print(JSON.stringify({",
    "        success: true,",
    "        message: 'S3 ListBuckets request completed',",
    "        bucketNames: bucketNames",
    "    }));",
    "    ",
    "} catch (error) {",
    "    print('// Error occurred: ' + error);",
    "    print('// Make sure your AWS credentials are valid and you have s3:ListAllMyBuckets permission');",
    "    ",
    "    // Return error result",
    "    print(JSON.stringify({",
    "        success: false,",
    "        message: 'S3 ListBuckets request failed',",
    "        error: error.toString(),",
    "        bucketNames: []",
    "    }));",
    "}"
]}
EOF

curl -s -H "X-TEO-Authorization: $TEO_AUTH" -X POST -d @d.json https://api.tetls.net/js | 
    tee test.json |
    jq -r .parsed_response_body

echo
