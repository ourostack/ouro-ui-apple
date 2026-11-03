// SiriEvaluations ships in the Xcode 27.3 beta SDK only. On Xcode 27.2 this file compiles to nothing. Compile-check
// it with Xcode 27.3 (README, "Siri AI"); it uses only the type name `SiriScenario`, so a change in its initializers
// cannot break it.
#if canImport(SiriEvaluations)
public import SiriEvaluations

extension OuroAXTesting.Wordings {
    /// One scenario per wording, made by `make`, for a SiriEvaluations test:
    ///
    /// ```swift
    /// let scenarios = wordings.scenarios { kind, text in SiriScenario { UserTurn(text) { Calls(AddItemIntent.self) } } }
    /// ```
    @available(iOS 27.3, macOS 27.3, *)
    public func scenarios(_ make: (_ kind: Kind, _ text: String) throws -> SiriScenario) rethrows -> [SiriScenario] {
        try all.map { try make($0.kind, $0.text) }
    }
}
#endif
