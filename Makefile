# -*- Makefile -*-
SHELL = /bin/sh
EMACS ?= emacs
EMACS_BATCH_OPTS=--batch -Q -L .
RM = @rm -rf

clean:
	$(RM) *~
	$(RM) \#*\#
	$(RM) *.elc

.PHONY: test compile

compile: clean
	@$(EMACS) ${EMACS_BATCH_OPTS} -l tests/my-byte-compile.el 2>&1 | grep -E "([Ee]rror|[Ww]arning):" && exit 1 || exit 0

test: compile clean
	@$(EMACS) ${EMACS_BATCH_OPTS} -l tests/wucuo-tests.el
