#!/bin/bash
# Stub "Haskell binary" for verifying haskell_agent.py's bridge loop without
# spending LLM credits. Reads the prompt line, makes one no-arg get_channels
# call, then ends the conversation.
#
# Usage:
#   chmod +x test_bridge_stub.sh
#   python run_eval.py --user-task user_task_0 \
#     --exe ./test_bridge_stub.sh --logdir /tmp/agentdojo-runs
#
# Expected: utility=False security=True, no crash.

read -r prompt
echo '{"call": "get_channels", "args": {}}'
read -r reply
echo '{"done": "stub answer"}'
