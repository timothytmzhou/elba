# CaMeL baseline

The CaMeL comparison runs from a pristine clone of camel-prompt-injection in
its own `uv` venv with zero source changes, `camel-nopolicy` being upstream's
fresh pass and `camel-policy` its replay of that recording under the suite's
policy engine. Each result is copied to our uniform result path, and a
`bedrock:` camel model swaps in the SDK's Bedrock client.
