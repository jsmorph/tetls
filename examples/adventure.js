// A program that plays an adventure game with GPT-4
//
// This program demonstrates arbitrary HTTP calls and getting good
// random numbers.
//
// See adventure.sh to run this program.

import * as std from 'std';

// Gather our final result here
var result = {};

// hpc = host procedure call
function hpc(o) {
    const x = std.open('hpc', 'w');
    x.puts(JSON.stringify(o));
    x.close();
    const y = std.open('hpc', 'r');
    const json = y.readAsString();
    return JSON.parse(json);
}

// Random byte mod n (and n better be less than 255)
function randn(n) {
    const r = hpc({'rng':{}});
    const b = r['bytes'][0];
    return b % n;
}

// Accumulate receipts for all RPCs here
var rpcs = [];

// Generic RPC
function rpc(api,request) {
    const o = {};
    o[api] = request;
    const response = hpc(o);
    o['response'] = response;
    rpcs.push(o);
    return JSON.parse(response['body']);
}

// Get an LLM completion via RPC
function llm(input,tokens) {
    const OPENAI_API_KEY = JSON.parse(std.getenv('TEO_JAVASCRIPT_ARG'));
    const request = {"input":input,
		     "model":"gpt-4",
		     "stream":false,
		     "max_output_tokens":tokens};
    const rpcRequest = {
        "url": "https://api.openai.com/v1/responses",
	"method": "POST",
	"headers": {
	    "Content-Type": "application/json",
            "Authorization": "Bearer " + OPENAI_API_KEY 
	},
        "body": JSON.stringify(request)
    };
    const endpointResponse = rpc("tlsp", rpcRequest);
    const output = endpointResponse['output'];
    const text = output[0]['content'][0]['text'];
    return text;
}

if (true) {
    const numRolls = 3;

    // Remember each roll here
    var rolls = [];
    const roll = function(x) {
	rolls.push(x);
	return x;
    };

    // Our array of messages for the LLM
    var input = [];

    input.push({"role":"system",
		"content":"You will run a fun, fantasy adventure text game for me.  You respond in JSON without any markdown, backticks, or anything that might interfere with parsing your response as JSON. Each response will have a JSON key for 'text' and another JSON key for 'actions' (an array of strings: the next possible actions)."});
    
    input.push({"role":"user",
		"content":"Set the scene (at JSON key 'text'), and then give me a choice of actions (at JSON key 'actions'), which is an array of strings."});
    
    for (let i = 1; i <= numRolls; i++) {
	// Here the entrypoint for the only I/O this program really does.
	const json = llm(input);
	const response = JSON.parse(json);
	const actions = response['actions']
	const n = randn(actions.length);
	const action = actions[n];
	roll({prompt:json, action: action});
	input.push({"role":"user",
		    "content":"My action: " + action + ". What happens next?"});
    }

    // Return all of the rolls
    result['rolls'] = rolls;
}

if (true) {
    // Also return all of the raw RPC data
    result['rpcs'] = rpcs;
}

print(JSON.stringify(result));
