import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("AirlineEmpireCore_AirlineEmpireCore.resources").path
        let buildPath = "/home/user/Airline-Empire/AirlineEmpireCore/.build-scan2/x86_64-unknown-linux-gnu/release/AirlineEmpireCore_AirlineEmpireCore.resources"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}