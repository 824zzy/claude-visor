//
//  SessionNavigator.swift
//  ClaudeVisor
//
//  Navigates to a Claude session's terminal split pane.
//  Uses TTY marker injection: writes a unique invisible marker to the
//  session's TTY device, then finds the pane containing that marker.
//  Deterministic match, no scoring heuristics.
//

import AppKit
import os.log

struct SessionNavigator {
    private static let logger = Logger(subsystem: "com.claudevisor", category: "Navigator")

    /// Navigate to the terminal split pane containing the given session
    static func navigateToSession(_ session: SessionState) {
        debugLog("Navigate: project=\(session.bestProjectName) pid=\(session.pid ?? -1) tty=\(session.tty ?? "none")")

        guard let ghostty = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").first else {
            debugLog("Ghostty not found")
            return
        }

        guard let tty = session.tty else {
            debugLog("No TTY, just activating Ghostty")
            ghostty.activate()
            return
        }

        let ghosttyPid = ghostty.processIdentifier
        let ttyPath = "/dev/\(tty)"

        // Step 1: Write a unique marker to the session's TTY
        let marker = "CV\(UInt32.random(in: 100000...999999))"
        guard writeMarkerToTTY(marker: marker, ttyPath: ttyPath) else {
            debugLog("Failed to write marker to \(ttyPath), falling back to activate only")
            ghostty.activate()
            return
        }
        debugLog("Wrote marker '\(marker)' to \(ttyPath)")

        // Step 2: Brief pause for terminal to render the marker
        usleep(150000)  // 150ms

        // Step 3: Find the pane containing the marker
        let clickTarget = findPaneWithMarker(marker: marker, ghosttyPid: ghosttyPid)

        // Step 4: Clear the marker
        clearMarker(ttyPath: ttyPath)

        // Step 5: Activate Ghostty and raise the correct window
        ghostty.activate()

        if let match = clickTarget {
            debugLog("Found marker in pane at (\(match.clickX), \(match.clickY))")

            // Raise the specific window containing the matched pane
            AXUIElementPerformAction(match.window, kAXRaiseAction as CFString)

            // Step 6: Click the pane after window is raised
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.3) {
                clickAtPosition(x: match.clickX, y: match.clickY)
                debugLog("Clicked pane at (\(match.clickX), \(match.clickY))")
            }
        } else {
            debugLog("Marker not found in any pane")
        }
    }

    // MARK: - TTY Marker

    /// Write a marker string to the TTY device (appears as terminal output, not input)
    private static func writeMarkerToTTY(marker: String, ttyPath: String) -> Bool {
        // Use ANSI: save cursor, write marker, restore cursor
        // This makes the marker appear in the buffer but minimizes visual disruption
        let sequence = "\u{1b}7\(marker)\u{1b}8"
        guard let handle = FileHandle(forWritingAtPath: ttyPath),
              let data = sequence.data(using: .utf8) else {
            return false
        }
        handle.write(data)
        handle.closeFile()
        return true
    }

    /// Clear the marker from the terminal display
    private static func clearMarker(ttyPath: String) {
        // Restore cursor position and clear to end of line
        let clearSequence = "\u{1b}8\u{1b}[K"
        if let handle = FileHandle(forWritingAtPath: ttyPath),
           let data = clearSequence.data(using: .utf8) {
            handle.write(data)
            handle.closeFile()
        }
    }

    // MARK: - Pane Matching

    /// Result of pane matching: the window to raise and coordinates to click
    private struct PaneMatch {
        let window: AXUIElement
        let clickX: CGFloat
        let clickY: CGFloat
    }

    /// Search all Ghostty panes for the marker string
    private static func findPaneWithMarker(marker: String, ghosttyPid: pid_t) -> PaneMatch? {
        let appElement = AXUIElementCreateApplication(ghosttyPid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            debugLog("Cannot access Ghostty windows")
            return nil
        }

        debugLog("Searching \(windows.count) windows for marker '\(marker)'")

        for (winIdx, window) in windows.enumerated() {
            var panes: [AXUIElement] = []
            collectLeafPanes(element: window, panes: &panes)

            for (paneIdx, pane) in panes.enumerated() {
                guard let pos = getPosition(of: pane),
                      let size = getSize(of: pane) else { continue }

                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(pane, kAXValueAttribute as CFString, &valueRef) == .success,
                   let content = valueRef as? String {
                    if content.contains(marker) {
                        debugLog("  MATCH: Window \(winIdx) Pane \(paneIdx) at (\(pos.x), \(pos.y))")
                        let clickX = pos.x + size.width / 2
                        let clickY = pos.y + size.height / 2
                        return PaneMatch(window: window, clickX: clickX, clickY: clickY)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Accessibility Helpers

    private static func collectLeafPanes(element: AXUIElement, panes: inout [AXUIElement]) {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        if role == "AXTextArea" {
            panes.append(element)
            return
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            collectLeafPanes(element: child, panes: &panes)
        }
    }

    private static func getPosition(of element: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        return point
    }

    private static func getSize(of element: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return size
    }

    private static func clickAtPosition(x: CGFloat, y: CGFloat) {
        let point = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .combinedSessionState)
        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }
        usleep(50000)
        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Debug Logging

    private static func debugLog(_ message: String) {
        let line = "\(Date()): \(message)\n"
        let path = NSHomeDirectory() + "/claude-visor-nav.log"
        if let data = line.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}
