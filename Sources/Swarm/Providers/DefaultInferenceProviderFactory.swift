// DefaultInferenceProviderFactory.swift
// Swarm Framework
//
// Opinionated default inference provider selection.
//
// LegacyAgent (the default tool-calling runtime) uses this factory to attempt
// Apple Foundation Models when no explicit inference provider is configured.

import Foundation

enum DefaultInferenceProviderFactory {
    static func makeFoundationModelsProviderIfAvailable() -> (any InferenceProvider)? {
        return nil
    }
}
