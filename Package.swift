// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation
let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"
let includeIntegrations = ProcessInfo.processInfo.environment["SWARM_INCLUDE_INTEGRATIONS"] == "1"
let coreOnly = !includeIntegrations

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
]

if includeIntegrations {
    packageProducts.append(.library(name: "SwarmOpenTelemetry", targets: ["SwarmOpenTelemetry"]))
    packageProducts.append(.library(name: "SwarmMembrane", targets: ["SwarmMembrane"]))
    packageProducts.append(.library(name: "SwarmMCP", targets: ["SwarmMCP"]))
}

if includeDemo, includeIntegrations {
    packageProducts.append(.executable(name: "SwarmDemo", targets: ["SwarmDemo"]))
    packageProducts.append(.executable(name: "SwarmMCPServerDemo", targets: ["SwarmMCPServerDemo"]))
}

var packageDependencies: [Package.Dependency] = [
    // swift-syntax range is intentionally widened to include 601/602 lines.
    //
    // Background: Xcode 26 (Swift 6.2.x) ships implicit SwiftPM prebuilts for
    // swift-syntax via the swiftlang "MacroSupport" prebuilt server. The 600.0.1
    // prebuilt is built against an older macOS SDK and fails to load on consumer
    // machines with "SDK does not match" warnings followed by
    // "Unable to find module dependency: 'SwiftSyntax'" errors. That prebuilt
    // download cannot be disabled from a consumer project (SWIFT_USE_PREBUILT_MACROS=NO,
    // IDESwiftPackageEnablePrebuilts=NO, SWIFTPM_DISABLE_PREBUILTS=1 and
    // -skipMacroValidation all fail to suppress it). Widening the range here lets
    // SwiftPM resolve to 601+ on Swift 6.2 toolchains, which does not ship the
    // broken prebuilt. Keep the upper bound below 603 while Conduit 0.3.x is
    // the latest compatible release line used by Swarm and Membrane.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.5"),
]

let integrationTrait = "Integrations"
if includeIntegrations {
    packageDependencies += [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.4.1"),
        .package(url: "https://github.com/docvarma/Wax.git", revision: "9400e49b2da34cf04e27aea608fd345b6d8c4952"),
        .package(
            url: "https://github.com/christopherkarani/Conduit",
            exact: "0.3.17",
            traits: [
                .trait(name: "OpenAI"),
                .trait(name: "OpenRouter"),
                .trait(name: "Anthropic"),
                .trait(name: "MLX"),
            ]
        ),
        .package(url: "https://github.com/christopherkarani/ContextCore.git", exact: "1.0.0"),
        .package(url: "https://github.com/christopherkarani/Membrane", revision: "11bef8184d8c7254c5e3d87dd2117e2932642d73"),
        .package(url: "https://github.com/christopherkarani/Hive", exact: "0.2.1"),
    ]
}

var swarmDependencies: [Target.Dependency] = [
    "SwarmMacros",
    .product(name: "Logging", package: "swift-log"),
    .product(name: "SwiftSoup", package: "SwiftSoup"),
]

var swarmSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

if !coreOnly {
    swarmDependencies += [
        .product(name: "Wax", package: "Wax", condition: .when(traits: [integrationTrait])),
        .product(name: "Conduit", package: "Conduit", condition: .when(traits: [integrationTrait])),

        .product(name: "ContextCore", package: "ContextCore", condition: .when(traits: [integrationTrait])),
        .product(name: "HiveCore", package: "Hive", condition: .when(traits: [integrationTrait])),
        .product(name: "Membrane", package: "Membrane", condition: .when(traits: [integrationTrait])),
        .product(name: "MembraneCore", package: "Membrane", condition: .when(traits: [integrationTrait])),

    ]
    swarmSwiftSettings.append(.define("SWARM_INTEGRATIONS", .when(traits: [integrationTrait])))
}

let swarmCoreOnlyExcludes = [
    "Integration/Wax",
    "Integration/Membrane/SessionMembraneAgentAdapter.swift",
    "Integration/Membrane/WaxMembraneStorage.swift",
    "Internal/GraphRuntime",
    "MCP",
    "Memory/ContextCoreMemory.swift",
    "Memory/DefaultAgentMemory.swift",
    "Providers/Conduit",
    "Providers/MultiProvider.swift",
    "Tools/Web",
    "Workflow/WorkflowCheckpointCodec.swift",
    "Workflow/WorkflowCheckpointStore.swift",
    "Workflow/WorkflowDurableEngine.swift",
]

var packageTargets: [Target] = [
    // MARK: - Macro Implementation (Compiler Plugin)
    .macro(
        name: "SwarmMacros",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),

    // MARK: - Main Library
    .target(
        name: "Swarm",
        dependencies: swarmDependencies,
        exclude: coreOnly ? swarmCoreOnlyExcludes : [],
        swiftSettings: swarmSwiftSettings
    ),

    // MARK: - Tests
    .testTarget(
        name: "SwarmTests",
        dependencies: ["Swarm"],
        resources: [],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "Swarm",
            "SwarmMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    )
]

if includeIntegrations {
    packageTargets.append(contentsOf: [
        .target(
            name: "SwarmOpenTelemetry",
            dependencies: [
                "Swarm",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
            ],
            swiftSettings: swarmSwiftSettings
        ),
        .target(
            name: "SwarmMembrane",
            dependencies: [
                "Swarm",
            ],
            path: "Sources/SwarmMembrane",
            swiftSettings: swarmSwiftSettings
        ),
        .target(
            name: "SwarmMCP",
            dependencies: [
                "Swarm",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: swarmSwiftSettings
        ),
        .target(
            name: "SwarmCapabilityShowcaseSupport",
            dependencies: [
                "Swarm",
                "SwarmMCP",
            ],
            swiftSettings: swarmSwiftSettings
        ),
        .executableTarget(
            name: "SwarmCapabilityShowcase",
            dependencies: [
                "SwarmCapabilityShowcaseSupport",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "HiveSwarmTests",
            dependencies: [
                "Swarm",
                .product(name: "HiveCore", package: "Hive")
            ],
            swiftSettings: swarmSwiftSettings
        ),
        .testTarget(
            name: "SwarmCapabilityShowcaseTests",
            dependencies: [
                "SwarmCapabilityShowcaseSupport",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwarmOpenTelemetryTests",
            dependencies: [
                "Swarm",
                "SwarmOpenTelemetry",
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ],
            swiftSettings: swarmSwiftSettings
        )
    ])
}

if includeDemo, includeIntegrations {
    packageTargets.append(
        .executableTarget(
            name: "SwarmDemo",
            dependencies: ["Swarm"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )

    packageTargets.append(
        .executableTarget(
            name: "SwarmMCPServerDemo",
            dependencies: [
                "Swarm",
                "SwarmMCP",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )
}

let package = Package(
    name: "Swarm",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
    ],
    products: packageProducts,
    traits: [
        .trait(
            name: integrationTrait,
            description: "Enable provider, memory, graph runtime, Wax, Membrane, ContextCore, Conduit, and Hive integrations."
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
