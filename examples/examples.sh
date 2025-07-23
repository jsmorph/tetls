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

