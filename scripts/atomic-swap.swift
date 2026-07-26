#!/usr/bin/env swift

import Darwin
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: atomic-swap.swift LEFT_PATH RIGHT_PATH\n".utf8)
    )
    Darwin.exit(64)
}

let leftPath = CommandLine.arguments[1]
let rightPath = CommandLine.arguments[2]
let result = leftPath.withCString { leftPointer in
    rightPath.withCString { rightPointer in
        renameatx_np(
            AT_FDCWD,
            leftPointer,
            AT_FDCWD,
            rightPointer,
            UInt32(RENAME_SWAP)
        )
    }
}

guard result == 0 else {
    let message = String(
        cString: strerror(errno)
    )
    FileHandle.standardError.write(
        Data("Atomic swap failed: \(message)\n".utf8)
    )
    Darwin.exit(1)
}
