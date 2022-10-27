import Foundation

typealias FeaturesHandler = (Result<Features, SDKError>) -> Void

/// View Model for Features
class FeaturesViewModel {
    let dataSource: FeaturesDataSource

    /// Caching Manager
    let cachingLayer: CachingLayer

    init(dataSource: FeaturesDataSource, cachingLayer: CachingLayer) {
        self.dataSource = dataSource
        self.cachingLayer = cachingLayer
    }

    func fetchCachedFeatures() -> Result<Features, SDKError> {
        // Check for cache data
        if let json = cachingLayer.getContent(fileName: Constants.featureCache) {
            let decoder = JSONDecoder()
            if let jsonPetitions = try? decoder.decode(FeaturesDataModel.self, from: json) {
                if let features = jsonPetitions.features {
                    return .success(features)
                } else {
                    logger.error("Failed parsed local data")
                    return.failure(.failedParsedData)
                }
            }
        }
        logger.error("Failed load local data")
        return .failure(.failedToLoadData)
    }
    
    /// Fetch Features
    func fetchFeatures(apiUrl: String?, completion: @escaping FeaturesHandler) {
        guard let apiUrl = apiUrl else {
            completion(.failure(.failedToLoadData))
            return
        }
        
        dataSource.fetchFeatures(apiUrl: apiUrl) { [weak self] result in
            switch result {
            case .success(let data):
                self?.prepareFeaturesData(data: data, completion: completion)
            case .failure(let error):
                completion(.failure(.failedToLoadData))
                logger.error("Failed get features: \(error.localizedDescription)")
            }
        }
    }

    /// Cache API Response and push success event
    private func prepareFeaturesData(data: Data, completion: @escaping FeaturesHandler) {
        cachingLayer.saveContent(fileName: Constants.featureCache, content: data)

        // Call Success Delegate with mention of data available with remote
        let decoder = JSONDecoder()

        if let jsonPetitions = try? decoder.decode(FeaturesDataModel.self, from: data) {
            guard let features = jsonPetitions.features else {
                completion(.failure(.failedParsedData))
                return
            }
            completion(.success(features))
        }
    }
}
