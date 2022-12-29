#!/bin/bash

xcodebuild -project GrowthBook-IOS.xcodeproj \
   -scheme GrowthBook \
   -sdk iphonesimulator \
   -destination 'platform=iOS Simulator,name=iPhone 14 Pro,OS=latest'

xcodebuild test -project GrowthBook-IOS.xcodeproj \
   -scheme GrowthBookTests \
   -sdk iphonesimulator \
   -destination 'platform=iOS Simulator,name=iPhone 14 Pro,OS=latest'
