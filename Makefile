PROJECT     := Thock.xcodeproj
SCHEME      := Thock
CONFIG      := Debug
DERIVED     := $(HOME)/Library/Developer/Xcode/DerivedData/Thock-make
PRODUCT     := $(DERIVED)/Build/Products/$(CONFIG)/Thock.app
APP         := build/Thock.app
BUNDLE_ID   := io.github.dailyxplorer.thock
DESTINATION := platform=macOS,arch=$(shell uname -m)

SIGNING := $(if $(CODE_SIGN_IDENTITY),CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)") \
           $(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)")

SHELL := /bin/bash

XCFILTER := 2>&1 | sed -E '/DVT|CoreSimulator|Simulator|Referenced from:|Expected in:|^Domain:|^Code: |^Failure Reason|^Recovery Suggestion|^Object:|^Method:|^Thread:|Please file a bug|^--$$|^Details:|xcodebuild: WARNING|appintentsmetadataprocessor|\{ platform:macOS|^$$/d'

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
              -derivedDataPath $(DERIVED) -destination '$(DESTINATION)' $(SIGNING)

.PHONY: all project build run probe probe-hid stop logs test reset-permissions packs preview render icon cpu latency verify-signature clean

all: build

project:
	@xcodegen generate --quiet

build: project
	@set -o pipefail; $(XCODEBUILD) build -quiet $(XCFILTER)
	@mkdir -p build && ln -sfn "$(PRODUCT)" "$(APP)"
	@echo "Built $(APP) -> $(PRODUCT)"

run: build stop
	@open "$(APP)"

probe: build stop
	@open "$(APP)" --args --probe
	@echo "Streaming probe log (Ctrl-C to stop). Only event type, stateID and PID are logged."
	@log stream --style compact --predicate 'subsystem == "$(BUNDLE_ID)" AND category == "probe"'

probe-hid: build stop
	@open "$(APP)" --args --probe --tap-level hid
	@log stream --style compact --predicate 'subsystem == "$(BUNDLE_ID)" AND category == "probe"'

stop:
	@pkill -x Thock 2>/dev/null || true

SINCE ?= 2m
logs:
	@log show --last $(SINCE) --style compact --predicate 'subsystem == "$(BUNDLE_ID)" OR (process == "tccd" AND eventMessage CONTAINS "$(BUNDLE_ID)") OR (sender == "Sandbox" AND eventMessage CONTAINS "Thock")' | cut -c1-260

test: project
	@set -o pipefail; $(XCODEBUILD) test $(XCFILTER) | grep -E "error:|warning:|✘|recorded an issue|Test run with|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|Testing failed|unexpected exit|crash"

verify-signature:
	@codesign --verify --strict --verbose=2 "$(APP)"
	@codesign -dvv --entitlements - "$(APP)" 2>&1 | grep -E 'Authority|flags|TeamIdentifier|security|Identifier=' || true
	@codesign -d -r- "$(APP)" 2>&1 | grep designated

reset-permissions:
	tccutil reset ListenEvent $(BUNDLE_ID)

packs:
	@bash Scripts/import-kbsim.sh Sources/Thock/Resources/Packs

PACK ?= holypanda
preview:
	@bash Scripts/preview-pack.sh Sources/Thock/Resources/Packs/$(PACK)

RENDERS := $(DERIVED)/renders
LABEL   ?= render
render: project
	@set -o pipefail; xcodebuild -project $(PROJECT) -scheme ThockRender -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination '$(DESTINATION)' build -quiet $(XCFILTER)
	@mkdir -p "$(RENDERS)" build && ln -sfn "$(RENDERS)" build/renders
	@"$(DERIVED)/Build/Products/$(CONFIG)/ThockRender" Sources/Thock/Resources/Packs/$(PACK) "$(RENDERS)/$(LABEL)_$(PACK).wav"

icon:
	@swift Scripts/generate-icon.swift Sources/Thock/Resources/Assets.xcassets

IDLE ?= 20
BENCH ?= 20
cpu: build
	@Scripts/measure-cpu.sh $(IDLE) $(BENCH)

latency: build stop
	@open "$(APP)" --args --measure-latency

clean:
	rm -rf build $(PROJECT) "$(DERIVED)"
