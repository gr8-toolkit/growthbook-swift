import XCTest

@testable import GrowthBook

class GrowthBookSDKBuilderTests: XCTestCase {
    let testURL = "https://host.com/api/features/4r23r324f23"
    let testAttributes: JSON = JSON()

    func testSDKInitializationDefault() throws {
        let sdkInstance = GrowthBookBuilder(hostURL: testURL,
                                        attributes: testAttributes,
                                        trackingCallback: { _, _ in }).initializer()
        
        XCTAssertTrue(sdkInstance.getGBContext().isEnabled)
        XCTAssertTrue(sdkInstance.getGBContext().hostURL == testURL)
        XCTAssertFalse(sdkInstance.getGBContext().isQaMode)
        XCTAssertTrue(sdkInstance.getGBContext().attributes == testAttributes)
        
    }
    
    func testSDKInitializationOverride() throws {
        
        let variations: [String: Int] = [:]

        let sdkInstance = GrowthBookBuilder(hostURL: testURL,
                                        attributes: testAttributes,
                                        trackingCallback: { _, _ in })
            .setEnabled(isEnabled: false)
            .setForcedVariations(forcedVariations: variations)
            .setQAMode(isEnabled: true)
            .initializer()

        XCTAssertFalse(sdkInstance.getGBContext().isEnabled)
        XCTAssertTrue(sdkInstance.getGBContext().hostURL == testURL)
        XCTAssertTrue(sdkInstance.getGBContext().isQaMode)
        XCTAssertTrue(sdkInstance.getGBContext().attributes == testAttributes)
        XCTAssertTrue(sdkInstance.getGBContext().forcedVariations == JSON(variations))
        
    }
    
    func testSDKInitializationData() throws {
        
        let variations: [String: Int] = [:]

        let sdkInstance = GrowthBookBuilder(hostURL: testURL,
                                        attributes: testAttributes,
                                        trackingCallback: { _, _ in })
            .setNetworkDispatcher(networkDispatcher: MockNetworkClient(successResponse: MockResponse().successResponse, error: nil))
            .setEnabled(isEnabled: false)
            .setForcedVariations(forcedVariations: variations)
            .setQAMode(isEnabled: true)
            .initializer()

        XCTAssertFalse(sdkInstance.getGBContext().isEnabled)
        XCTAssertTrue(sdkInstance.getGBContext().hostURL == testURL)
        XCTAssertTrue(sdkInstance.getGBContext().isQaMode)
        XCTAssertTrue(sdkInstance.getGBContext().attributes == testAttributes)
        
    }
    
    func testSDKFeaturesData() throws {
        let sdkInstance = GrowthBookBuilder(hostURL: testURL,
                                        attributes: testAttributes,
                                        trackingCallback: { _, _ in })
            .setNetworkDispatcher(networkDispatcher: MockNetworkClient(successResponse: MockResponse().successResponse, error: nil))
            .initializer()
        
        let completedExpectation = expectation(description: "Completed")
        
        sdkInstance.refreshCache { _ in
            XCTAssertTrue(sdkInstance.getFeatures().contains(where: {$0.key == "onboarding"}))
            XCTAssertFalse(sdkInstance.getFeatures().contains(where: {$0.key == "fwrfewrfe"}))
            completedExpectation.fulfill()
        }

        waitForExpectations(timeout: 0.3, handler: nil)
    }
    
    func testSDKRunMethods() throws {
        let sdkInstance = GrowthBookBuilder(hostURL: testURL,
                                        attributes: testAttributes,
                                        trackingCallback: { _, _ in })
            .setNetworkDispatcher(networkDispatcher: MockNetworkClient(successResponse: MockResponse().successResponse, error: nil)).initializer()
        
        let featureValue = sdkInstance.evalFeature(id: "fwrfewrfe")
        XCTAssertTrue(featureValue.source == FeatureSource.unknownFeature.rawValue)
        
        let expValue = sdkInstance.run(experiment: Experiment(key: "fwewrwefw"))
        XCTAssertTrue(expValue.variationId == 0)
    }
    func testEncrypt() throws {
        let sdkInstance = GrowthBookBuilder(hostURL: testURL,
                                        attributes: testAttributes,
                                        trackingCallback: { _, _ in }).initializer()
        let decoder = JSONDecoder()
        let keyString = "Ns04T5n9+59rl2x3SlNHtQ=="
        let encryptedFeatures = "vMSg2Bj/IurObDsWVmvkUg==.L6qtQkIzKDoE2Dix6IAKDcVel8PHUnzJ7JjmLjFZFQDqidRIoCxKmvxvUj2kTuHFTQ3/NJ3D6XhxhXXv2+dsXpw5woQf0eAgqrcxHrbtFORs18tRXRZza7zqgzwvcznx"
        let expectedResult = "{\"testfeature1\":{\"defaultValue\":true,\"rules\":[{\"condition\":{\"id\":\"1234\"},\"force\":false}]}}"
        sdkInstance.setEncryptedFeatures(encryptedString: encryptedFeatures, encryptionKey: keyString)
        guard
            let dataExpectedResult = expectedResult.data(using: .utf8),
            let features = try? decoder.decode([String: Feature].self, from: dataExpectedResult)
        else {
            XCTFail()
            return
        }
        XCTAssertTrue(sdkInstance.gbContext.features["testfeature1"]?.rules?[0].condition == features["testfeature1"]?.rules?[0].condition)
        XCTAssertTrue(sdkInstance.gbContext.features["testfeature1"]?.rules?[0].force == features["testfeature1"]?.rules?[0].force)
    }
}
