# Builds use only the Command Line Tools. swift-testing's macro plugin ships with them
# but SwiftPM does not find it on its own, so point the compiler at it.
CLT=/Library/Developer/CommandLineTools
TEST_FLAGS=()
if [ -d "$CLT/usr/lib/swift/host/plugins/testing" ]; then
  TEST_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing")
fi

# SwiftLint, run by `swift package format`, looks for sourcekitd under Xcode
# and crashes without it. The Command Line Tools have a copy.
export TOOLCHAIN_DIR=$CLT
