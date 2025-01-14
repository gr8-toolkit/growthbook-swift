import Foundation

/// GrowthBookBuilder - Root Class for SDK Initializers for GrowthBook SDK
protocol GrowthBookProtocol: AnyObject {
    var growthBookBuilderModel: GrowthBookModel { get set }

    func setForcedVariations(forcedVariations: [String: Int]) -> GrowthBookBuilder
    func setQAMode(isEnabled: Bool) -> GrowthBookBuilder
    func setEnabled(isEnabled: Bool) -> GrowthBookBuilder
    func initializer() -> GrowthBookSDK
}

public struct GrowthBookModel {
    var hostURL: String?
    var features: Data?
    var attributes: JSON
    var trackingClosure: TrackingCallback
    var logLevel: Level = .info
    var isQaMode: Bool = false
    var isEnabled: Bool = true
    var forcedVariations: JSON?
}

/// GrowthBookBuilder - inItializer for GrowthBook SDK for Apps
/// - HostURL - Server URL
/// - UserAttributes - User Attributes
/// - Tracking Closure - Track Events for Experiments
@objc public class GrowthBookBuilder: NSObject, GrowthBookProtocol {
    var growthBookBuilderModel: GrowthBookModel

    private var networkDispatcher: NetworkProtocol = CoreNetworkClient()

    @objc public init(hostURL: String, attributes: [String: Any], trackingCallback: @escaping TrackingCallback) {
        growthBookBuilderModel = GrowthBookModel(hostURL: hostURL, attributes: JSON(attributes), trackingClosure: trackingCallback)
    }

    @objc public init(features: Data, attributes: [String: Any], trackingCallback: @escaping TrackingCallback) {
        growthBookBuilderModel = GrowthBookModel(features: features, attributes: JSON(attributes), trackingClosure: trackingCallback)
    }
    
    @objc public init(hostURL: String?, features: Data?, attributes: [String: Any], trackingCallback: @escaping TrackingCallback) {
        growthBookBuilderModel = GrowthBookModel(hostURL: hostURL, features: features, attributes: JSON(attributes), trackingClosure: trackingCallback)
    }

    init(hostURL: String, attributes: JSON, trackingCallback: @escaping TrackingCallback) {
        growthBookBuilderModel = GrowthBookModel(hostURL: hostURL, attributes: JSON(attributes), trackingClosure: trackingCallback)
    }

    /// Set Network Client - Network Client for Making API Calls
    @objc public func setNetworkDispatcher(networkDispatcher: NetworkProtocol) -> GrowthBookBuilder {
        self.networkDispatcher = networkDispatcher
        return self
    }

    /// Set log level for SDK Logger
    ///
    /// By default log level is set to `info`
    @objc public func setLogLevel(_ level: LoggerLevel) -> GrowthBookBuilder {
        growthBookBuilderModel.logLevel = Logger.getLoggingLevel(from: level)
        return self
    }

    @objc public func setForcedVariations(forcedVariations: [String: Int]) -> GrowthBookBuilder {
        growthBookBuilderModel.forcedVariations = JSON(forcedVariations)
        return self
    }

    @objc public func setQAMode(isEnabled: Bool) -> GrowthBookBuilder {
        growthBookBuilderModel.isQaMode = isEnabled
        return self
    }

    @objc public func setEnabled(isEnabled: Bool) -> GrowthBookBuilder {
        growthBookBuilderModel.isEnabled = isEnabled
        return self
    }

    @objc public func initializer() -> GrowthBookSDK {
        let gbContext = Context(
            hostURL: growthBookBuilderModel.hostURL,
            isEnabled: growthBookBuilderModel.isEnabled,
            attributes: growthBookBuilderModel.attributes,
            forcedVariations: growthBookBuilderModel.forcedVariations,
            isQaMode: growthBookBuilderModel.isQaMode,
            trackingClosure: growthBookBuilderModel.trackingClosure
        )
        if let features = growthBookBuilderModel.features {
            CachingManager.shared.saveContent(fileName: Constants.featureCache, content: features)
        }
        return GrowthBookSDK(context: gbContext, networkDispatcher: networkDispatcher)
    }
}

/// The main export of the libraries is a simple GrowthBook wrapper class that takes a Context object in the constructor.
///
/// It exposes two main methods: feature and run.
@objc public class GrowthBookSDK: NSObject {
    private var networkDispatcher: NetworkProtocol
    public var gbContext: Context
    private var featureVM: FeaturesViewModel!
    
    private let queue = DispatchQueue(
        label: "Growthbook.\(UUID().uuidString)",
        attributes: .concurrent
    )

    init(context: Context,
         logLevel: Level = .info,
         networkDispatcher: NetworkProtocol = CoreNetworkClient(),
         features: Features? = nil) {
        gbContext = context
        self.networkDispatcher = networkDispatcher
        super.init()
        self.featureVM = FeaturesViewModel(dataSource: FeaturesDataSource(dispatcher: networkDispatcher), cachingLayer: CachingManager.shared)
        if let features = features {
            gbContext.features = features
        } else {
            refreshCacheInternal()
            
            if case let .success(features) = featureVM.fetchCachedFeatures() {
                gbContext.features = features
            }
        }
        // Logger setup. if we have logHandler we have to re-initialise logger
        logger.minLevel = logLevel
    }

    /// Manually Refresh Cache
    @objc public func refreshCache(completion: CacheRefreshHandler?) {
        refreshCacheInternal(url: gbContext.hostURL, completion: completion)
    }

    /// Get Context - Holding the complete data regarding cached features & attributes etc.
    @objc public func getGBContext() -> Context {
        return queue.sync {
            gbContext
        }
    }

    /// Get Cached Features
    @objc public func getFeatures() -> [String: Feature] {
        var features: [String: Feature] = [:]
        queue.sync {
            features = gbContext.features
        }
        return features
    }

    /// Get the value of the feature with a fallback
    public func getFeatureValue(feature id: String, default defaultValue: JSON) -> JSON {
        return queue.sync { FeatureEvaluator().evaluateFeature(context: gbContext, featureKey: id).value ?? defaultValue }
    }

        /// The setEncryptedFeatures method takes an encrypted string with an encryption key and then decrypts it with the default method of decrypting or with a method of decrypting from the user
    @objc public func setEncryptedFeatures(encryptedString: String, encryptionKey: String, subtle: CryptoProtocol? = nil) {
        let crypto: CryptoProtocol = subtle ?? Crypto()
        let decoder = JSONDecoder()
        let arrayEncryptedString = encryptedString.components(separatedBy: ".")
       
        guard let iv = arrayEncryptedString.first,
              let cipherText = arrayEncryptedString.last,
              let keyBase64 = Data(base64Encoded: encryptionKey),
              let ivBase64 = Data(base64Encoded: iv),
              let cipherTextBase64 = Data(base64Encoded: cipherText),
              let plainTextBuffer = try? crypto.decrypt(key: keyBase64.map{$0},
                                                                    iv: ivBase64.map{$0},
                                                                    cypherText: cipherTextBase64.map{$0}),
              let features = try? decoder.decode([String: Feature].self, from: Data(plainTextBuffer))
        else { return }

        queue.async(flags: .barrier) { [weak gbContext] in
            gbContext?.features = features
        }
    }

    /// The feature method takes a single string argument, which is the unique identifier for the feature and returns a FeatureResult object.
    @objc public func evalFeature(id: String) -> FeatureResult {
        return queue.sync { FeatureEvaluator().evaluateFeature(context: gbContext, featureKey: id) }
    }

    /// The isOn method takes a single string argument, which is the unique identifier for the feature and returns the feature state on/off
    @objc public func isOn(feature id: String) -> Bool {
        return evalFeature(id: id).isOn
    }

    /// The run method takes an Experiment object and returns an experiment result
    @objc public func run(experiment: Experiment) -> ExperimentResult {
        return queue.sync { ExperimentEvaluator().evaluateExperiment(context: gbContext, experiment: experiment) }
    }

    /// The setAttributes method replaces the Map of user attributes that are used to assign variations
    @objc public func setAttributes(attributes: Any) {
        queue.async(flags: .barrier) { [weak gbContext] in
            gbContext?.attributes = JSON(attributes)
        }
    }
    
    private func refreshCacheInternal(url: String? = nil, completion: CacheRefreshHandler? = nil) {
        featureVM.fetchFeatures(apiUrl: url) {[weak self] result in
            switch result {
                case .success(let features):
                    self?.queue.async(flags: .barrier) {
                        self?.gbContext.features = features
                        self?.queue.async {
                            completion?(true)
                        }
                    }

                case .failure:
                    self?.queue.async {
                        completion?(false)
                    }
            }
        }
    }
}
