.PHONY: run

STAMP := agents/.install-stamp
SRCS := $(wildcard agents/*.hs) agents/agents.cabal

$(STAMP): $(SRCS)
	cd agents && cabal install --lib agents --force-reinstalls
	@touch $@

run: $(STAMP)
	cd agents && cabal run $(filter-out $@,$(MAKECMDGOALS))

%:
	@:
