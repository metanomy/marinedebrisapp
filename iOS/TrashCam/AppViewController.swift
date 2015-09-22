//
//  AppViewController.swift
//  TrashCam
//
//  Created by Justin Driscoll on 9/21/15.
//  Copyright © 2015 Makalu, Inc. All rights reserved.
//

import UIKit
import CoreLocation
import ImageIO

class AppViewController: UIViewController {

    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var imageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIImagePickerController.isSourceTypeAvailable(.Camera) {
            state = .RequestingLocation
        }
        else {
            state = .CameraNotAvailable
        }
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        if state == .CameraNotAvailable {
            showCameraUnavailableMessage()
        }
    }

    // MARK - State

    private let locationManager = CLLocationManager()

    internal enum State: Int, Comparable {
        case Loaded
        case CheckingNetworkAvailabliity // TODO
        case NetworkNotAvailable // TODO
        case CameraNotAvailable
        case RequestingLocation
        case RequestingLocationAuthorization
        case LocationAccessDenied
        case LocationAccessAllowed
        case WaitingForLocation
        case LocationFound
        case PresentingCamera
        case UploadingImage
    }

    private var state: State = .Loaded {
        didSet {
            if oldValue == state {
                return
            }
            print("State did change:", oldValue, "->", state)
            switch state {
            case .CameraNotAvailable:
                statusLabel.text = "Camera not found"
            case .RequestingLocation:
                locationManager.delegate = self
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
            case .RequestingLocationAuthorization:
                statusLabel.text = "Requesting location access..."
                locationManager.requestWhenInUseAuthorization()
            case .LocationAccessDenied:
                statusLabel.text = "Location access denied"
                locationManager.stopUpdatingLocation()
                showLocationUnavailableMessage()
            case .LocationAccessAllowed:
                startUpdatingLocation()
            case .WaitingForLocation:
                statusLabel.text = "Getting your location..."
                locationManager.startUpdatingLocation()
            case .LocationFound:
                statusLabel.text = "Ready!"
                print("Location found", locationManager.location)
                showCamera()
            default:
                break
            }
        }
    }

    func startUpdatingLocation() {
        if state == .LocationAccessDenied || state > State.LocationAccessAllowed {
            return
        }
        state = .WaitingForLocation
    }

    func showCamera() {
        guard state == .LocationFound else {
            return
        }
        state = .PresentingCamera
        let controller = UIImagePickerController()
        controller.sourceType = .Camera
        controller.cameraFlashMode = .Auto
        controller.allowsEditing = false
        controller.delegate = self
        presentViewController(controller, animated: true, completion: nil)
    }
}

// Simple operator functions to simplify state comparisons
internal func <(lhs: AppViewController.State, rhs: AppViewController.State) -> Bool {
    return lhs.rawValue < rhs.rawValue
}

internal func ==(lhs: AppViewController.State, rhs: AppViewController.State) -> Bool {
    return lhs.rawValue == rhs.rawValue
}


// MARK - Location manager delegate
extension AppViewController: CLLocationManagerDelegate {

    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        switch status {
        case .NotDetermined:
            state = .RequestingLocationAuthorization
        case .Restricted,
        .Denied:
            state = .LocationAccessDenied
        default:
            state = .LocationAccessAllowed
        }
    }

    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let _ = locations.last where state < .LocationFound {
            state = .LocationFound
        }
    }
}


// MARK - Alerts
extension AppViewController {

    private final func canOpenSettings() -> Bool {
        guard let url = NSURL(string: UIApplicationOpenSettingsURLString) else {
            return false
        }
        return UIApplication.sharedApplication().canOpenURL(url)
    }

    private final func showLocationUnavailableMessage() {

        let alertController = UIAlertController(title: "Location Unavailable", message: "Please enable location access.", preferredStyle: .Alert)

        alertController.addAction(UIAlertAction(title: "Dismiss", style: .Cancel, handler: nil))

        if canOpenSettings() {
            alertController.addAction(UIAlertAction(title: "Open Settings", style: .Default, handler: { action in
                if let url = NSURL(string: UIApplicationOpenSettingsURLString) {
                    UIApplication.sharedApplication().openURL(url)
                }
            }))
        }

        presentViewController(alertController, animated: true, completion: nil)
    }

    private final func showCameraUnavailableMessage() {

        let alertController = UIAlertController(title: "Camera Unavailable", message: "This app requires a camera to use.", preferredStyle: .Alert)

        alertController.addAction(UIAlertAction(title: "Dismiss", style: .Cancel, handler: nil))

        presentViewController(alertController, animated: true, completion: nil)
    }
}

// MARK - Image picker controller delegate
extension AppViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {

        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            let alertController = UIAlertController(title: "Image Error", message: "There was an error creating the image please try again.", preferredStyle: .Alert)
            alertController.addAction(UIAlertAction(title: "Dismiss", style: .Cancel, handler: nil))
            presentViewController(alertController, animated: true, completion: nil)
            return
        }

        guard let location = self.locationManager.location else {
            let alertController = UIAlertController(title: "Location Unavailable", message: "Unable to get the current location. Please try again.", preferredStyle: .Alert)
            alertController.addAction(UIAlertAction(title: "Dismiss", style: .Cancel, handler: nil))
            presentViewController(alertController, animated: true, completion: nil)
            return
        }

        let maxImageDimension = 1536
        let maxSize = image.sizeThatFits(CGSize(width: maxImageDimension, height: maxImageDimension))
        let resizedImage = image.resize(maxSize, quality: .High)
        let mimetype = "image/jpeg"

        var metadata: [String: AnyObject] = [:]
        if let originalMetadata = info[UIImagePickerControllerMediaMetadata]?.mutableCopy() as? NSDictionary {
            metadata = originalMetadata.mutableCopy() as! [String: AnyObject]

            // Need to strip the orientation info from the EXIF metadata because the resize
            // routine always returns the data facing up
            metadata[kCGImagePropertyOrientation as String] = nil
        }

        if let data = resizedImage.asDataWithMetadata(metadata, mimetype: mimetype, location: location, heading: locationManager.heading) {

            let documentsDirURL = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
            let fileURL = documentsDirURL.URLByAppendingPathComponent("test.jpg")
            data.writeToURL(fileURL, atomically: false)

            print("image", fileURL)
            let newImage = UIImage(contentsOfFile: fileURL.path!)
            imageView.image = newImage
        }
        else {
            print("NO DATA")
        }

        dismissViewControllerAnimated(true) {
            //self.state = .LocationFound
        }
    }

    func imagePickerControllerDidCancel(picker: UIImagePickerController) {
        dismissViewControllerAnimated(true) {
            //self.state = .LocationFound
        }
    }
}



