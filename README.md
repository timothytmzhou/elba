Installation
------------
Install `llm`:
```
pip install llm
```
Add your openai key:
```
# Paste your OpenAI API key into this
llm keys set openai
```
Run 
```
cabal install --lib agents --force-reinstalls
```
so that the `agents` library is available to GHCi. 
You must re-run this command after any changes to the `agents` library.
