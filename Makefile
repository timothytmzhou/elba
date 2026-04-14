.PHONY: run build

build:
	cabal build --write-ghc-environment-files=always all

run: build
	cabal run $(filter-out $@,$(MAKECMDGOALS))

%:
	@:
