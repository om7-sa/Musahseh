import Foundation
import IOKit.pwr_mgt

var assertion: IOPMAssertionID = 0
let result = IOPMAssertionCreateWithName(
    kIOPMAssertionTypePreventSystemSleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "مصحصح: اختبار طلب الطاقة" as CFString,
    &assertion
)

guard result == kIOReturnSuccess, assertion != 0 else {
    fputs("PreventSystemSleep assertion failed: \(result)\n", stderr)
    exit(1)
}

let releaseResult = IOPMAssertionRelease(assertion)
guard releaseResult == kIOReturnSuccess else {
    fputs("Assertion release failed: \(releaseResult)\n", stderr)
    exit(2)
}

print("PreventSystemSleep assertion: OK")
