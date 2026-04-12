.PHONY: build dmg clean open

build:
	swift build -c release

dmg:
	chmod +x scripts/make-dmg.sh
	./scripts/make-dmg.sh

clean:
	rm -rf .build dist build
	swift package clean

open:
	xed CoolifyDeployBar.xcodeproj

open-package:
	xed Package.swift
