//===----------------------------------------------------------------------===//
// ServiceResolver — orders services by their `depends_on` graph.
//
// Produces a start order (dependencies first) and detects cycles. Services
// with no dependencies are ordered by their declaration order in the file.
//===----------------------------------------------------------------------===//

import Foundation

/// Orders services topologically by their `depends_on` graph.
public enum ServiceResolver {
    /// Return the service names in start order: every service appears after
    /// all of its dependencies. Throws on a cycle.
    public static func resolve(_ project: ComposeProject) throws -> [String] {
        let services = project.services
        var visited: Set<String> = []
        var inProgress: Set<String> = []
        var order: [String] = []
        var stack: [String] = []

        func visit(_ name: String) throws {
            if inProgress.contains(name) {
                // Reconstruct the cycle from the stack.
                let cycleStart = stack.firstIndex(of: name) ?? 0
                let cycle = Array(stack[cycleStart...]) + [name]
                throw ComposeParseError.circularDependency(cycle)
            }
            if visited.contains(name) { return }
            inProgress.insert(name)
            stack.append(name)

            let service = services[name]
            for dep in service?.dependsOn.keys.sorted() ?? [] {
                try visit(dep)
            }

            stack.removeLast()
            inProgress.remove(name)
            visited.insert(name)
            order.append(name)
        }

        for name in services.keys.sorted() {
            try visit(name)
        }
        return order
    }
}
