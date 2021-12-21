//
//  MainViewController.swift
//  MyAlbum
//
//  Created by nju on 2021/12/21.
//

import UIKit
import CoreMedia
import CoreML
import Vision

class MainViewController: UIViewController {
    var TypeDict:Dictionary<String,[UIImage]>=[:]
    var TypeInfo:Dictionary<String,Int>=[:]
    @IBOutlet weak var ImageView: UIImageView!
    @IBOutlet weak var resultLabel: UILabel!
    override func viewDidLoad() {
        super.viewDidLoad()
        resultLabel.text="choose or take a photo"
        //loadImages()
        // Do any additional setup after loading the view.
    }
    
    let semphore = DispatchSemaphore(value: MainViewController.maxInflightBuffer)
    var inflightBuffer = 0
    static let maxInflightBuffer = 2

    lazy var classificationRequest: VNCoreMLRequest = {
        do{
            let classifier = try snacks(configuration: MLModelConfiguration())
            
            let model = try VNCoreMLModel(for: classifier.model)
            let request = VNCoreMLRequest(model: model, completionHandler: {
                [weak self] request,error in
                self?.processObservations(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
            
            
        } catch {
            fatalError("Failed to create request")
        }
    }()
    
    @IBAction func choose_image(_ sender: UIButton) {
        presentPhotoPicker(sourceType: .photoLibrary)
    }
    @IBAction func take_photo(_ sender: Any) {
        presentPhotoPicker(sourceType: .camera)
    }
    
    func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
      picker.sourceType = sourceType
      present(picker, animated: true)
    }
    
    func classify(image: UIImage) {
        semphore.wait()
        inflightBuffer += 1
        if inflightBuffer >= MainViewController.maxInflightBuffer {
            inflightBuffer = 0
        }
        DispatchQueue.main.async {
            //let _image=image.resizeImageTo(size: CGSize(width: 299, height: 299))
            var pixelbuffer=self.buffer(from: image)
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelbuffer!, options: [:])
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                print("Failed to perform classification: \(error)")
            }
            self.semphore.signal()
        }
    }
    
    func buffer(from image: UIImage) -> CVPixelBuffer? {
      let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
      var pixelBuffer : CVPixelBuffer?
      let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
      guard (status == kCVReturnSuccess) else {
        return nil
      }

      CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
      let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

      let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
      let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

      context?.translateBy(x: 0, y: image.size.height)
      context?.scaleBy(x: 1.0, y: -1.0)

      UIGraphicsPushContext(context!)
      image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
      UIGraphicsPopContext()
      CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

      return pixelBuffer
    }

    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let typeDetail=segue.destination as! TypeCollectionViewController
        typeDetail.TypeDict=self.TypeDict
    }
    

}

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
    picker.dismiss(animated: true)

    let image = info[.originalImage] as! UIImage
    ImageView.image=image
      classify(image: image)


  }
}

extension MainViewController {
    func processObservations(for request: VNRequest, error: Error?) {
        if let results = request.results as? [VNClassificationObservation] {
            if results.isEmpty {
                self.resultLabel.text = "Nothing found"
            } else {
                let result = results[0].identifier
                let confidence = results[0].confidence
                if confidence>0.6{
                    self.resultLabel.text = result+"\r\n"+String(format: "%.1f%%", confidence * 100)
                    if TypeDict[result]==nil{
                        TypeDict[result]=[]
                    }
                    TypeDict[result]?.append(ImageView.image!)
                    //saveImage()
                }else{
                    self.resultLabel.text = "I'm not sure..."
                }
                print(result)
            }
        } else if let error = error {
            self.resultLabel.text = "Error: \(error.localizedDescription)"
        } else {
            self.resultLabel.text = "???"
        }
    }
}

extension MainViewController{
    func dataFilePath()->URL{
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return path!.appendingPathComponent("TodoItems.json")
    }
    
    func saveImage(){
        do{
            
            
            for key in TypeDict.keys{
                TypeInfo[key]=TypeDict[key]?.count
                if TypeInfo[key]!<=0{
                    continue
                }
                    UserDefaults.standard.set(TypeInfo[key], forKey: "imageCount")
                            UserDefaults.standard.synchronize()
                let imageCount = UserDefaults.standard.integer(forKey: "imageCount")
                var filePath = ""
                for i in 0...imageCount-1{
                    let fileManager = FileManager.default
                                    let rootPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! as NSString
                    filePath = "\(rootPath)/\(key)/\(i).jpg"
                    fileManager.createFile(atPath: filePath, contents: ((TypeDict[key]?[i])!.pngData()), attributes: nil)
                }
                print(key)
                print(TypeInfo[key]!)
            }
            let data = try JSONEncoder().encode(TypeInfo)
            try data.write(to: dataFilePath(), options: .atomic)
        }catch{
            print("Can not save: \(error.localizedDescription)")
        }
    }
    func loadImages(){
        TypeDict=[:]
        let path = dataFilePath()
        if let data = try? Data(contentsOf: path){
            do{
                TypeInfo=try JSONDecoder().decode(Dictionary<String,Int>.self, from: data)
                print(TypeInfo)
                for key in TypeInfo.keys{
                    TypeDict[key]=[]
                    UserDefaults.standard.set(TypeInfo[key], forKey: "imageCount")
                                UserDefaults.standard.synchronize()
                    let imageCount = UserDefaults.standard.integer(forKey: "imageCount")
                    if imageCount<=0{
                        continue
                    }
                    var filePath = ""
                    for i in 0...imageCount-1{
                        let fileManager = FileManager.default
                                        let rootPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! as NSString
                        filePath = "\(rootPath)/\(key)/\(i).jpg"
                        if fileManager.fileExists(atPath: filePath) {
                                            if let imageData = fileManager.contents(atPath: filePath) {
                                                //data转String
                                                if let imageImage = UIImage.init(data: imageData) {
                                                    self.TypeDict[key]!.append(imageImage)
                                                }
                                            }
                                        }

                    }
                    TypeInfo[key]=TypeDict[key]?.count
                    print(key)
                    print(TypeInfo[key]!)
                }
            }catch{
                print("Error decoding list:\(error.localizedDescription)")
            }
        }
    }
}
