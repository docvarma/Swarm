//
//  LanguageModelSession.swift
//  Swarm
//
//  Created by Chris Karani on 16/01/2026.
//

import Foundation

// Gate FoundationModels import for cross-platform builds (Linux, Windows, etc.)
#if canImport(FoundationModels)
    import FoundationModels

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    extension LanguageModelSession: InferenceProvider {
        public func generate(prompt: String, options: InferenceOptions) async throws -> String {
            // Foundation Models has a 4096-token context window.
            // Enforce a hard character limit as a safety net (~1024 chars ≈ 256 tokens reserve).
            let maxChars = 3072 * 4
            let safePrompt: String
            if prompt.count > maxChars {
                let marker = "\n\n[... truncated to fit FM context window ...]\n\n"
                let headLen = max(256, (maxChars / 2) - marker.count)
                let tailLen = maxChars - headLen - marker.count
                let head = prompt.prefix(headLen)
                let tail = prompt.suffix(tailLen)
                safePrompt = String(head) + marker + String(tail)
            } else {
                safePrompt = prompt
            }

            let response = try await respond(to: safePrompt)
            var content = response.content

            // Handle manual stop sequences since Foundation Models might not support them natively via this API.
            // Find the earliest occurring stop sequence and truncate at that point.
            var earliestStop: String.Index? = nil
            for stopSequence in options.stopSequences {
                if let range = content.range(of: stopSequence) {
                    if earliestStop == nil || range.lowerBound < earliestStop! {
                        earliestStop = range.lowerBound
                    }
                }
            }
            if let stop = earliestStop {
                content = String(content[..<stop])
            }

            return content
        }

        // `Error` must be qualified here: the macOS 27 SDK adds a nested
        // `LanguageModelSession.Error`, which member lookup would otherwise
        // resolve instead of the global `Swift.Error` the protocol requires.
        public func stream(prompt: String, options _: InferenceOptions) -> AsyncThrowingStream<String, any Swift.Error> {
            StreamHelper.makeTrackedStream { continuation in
                do {
                    // For streaming, we'll generate the full response and yield it.
                    for try await stream in self.streamResponse(to: prompt) {
                        continuation.yield(stream.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    throw AgentError.cancelled
                }
            }
        }

        public func generateWithToolCalls(
            prompt: String,
            tools: [ToolSchema],
            options: InferenceOptions
        ) async throws -> InferenceResponse {
            try await LanguageModelSessionToolCallingEmulation.generateResponse(
                prompt: prompt,
                tools: tools,
                options: options
            ) { toolPrompt, options in
                // Enforce hard 4096-token cap for Foundation Models after tool defs are added.
                // Empirical measurement: FM tokenizer uses ~1.09 chars/token for tool-call
                // prompts with JSON + code. Reserve ~800 tokens for output + overhead.
                // 3296 input tokens × 1.09 ≈ 3,593 chars. Use 2,800 for safety margin
                // after tool defs are added by buildToolPrompt.
                let maxChars = 2_800
                let safePrompt: String
                if toolPrompt.count > maxChars {
                    let marker = "\n\n[... truncated to fit FM context window ...]\n\n"
                    let headLen = max(512, (maxChars / 2) - marker.count)
                    let tailLen = maxChars - headLen - marker.count
                    let head = toolPrompt.prefix(headLen)
                    let tail = toolPrompt.suffix(tailLen)
                    safePrompt = String(head) + marker + String(tail)
                } else {
                    safePrompt = toolPrompt
                }
                return try await self.generate(prompt: safePrompt, options: options)
            }
        }
    }
#endif
