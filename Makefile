# -*- Makefile -*-
SHELL = /bin/sh
EMACS ?= emacs

clean:
	@rm -f *~
	@rm -f \#*\#
	@rm -f *.elc

.PHONY: test

test: clean
	@$(EMACS) -batch -Q -L . -l tests/wucuo-tests.el
