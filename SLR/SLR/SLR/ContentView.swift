import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
//import Alamofire

import SwiftUI
import UIKit
import Photos
import AVKit


struct VideoCaptureView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: VideoCaptureView

        init(_ parent: VideoCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.isPresented = false
            guard let videoURL = info[.mediaURL] as? URL else { return }
            
            // 保存视频到相册
            UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, self, #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
        }
        
        @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
            if let error = error {
                print("保存视频失败: \(error.localizedDescription)")
            } else {
                print("视频已保存到相册")
            }
        }
    }
}

struct RoundedAndShadowProButtonStyle: ButtonStyle {
    @Environment(\.controlSize) var controlSize
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width:150, height: 20, alignment: .center)
            .foregroundColor(.white)
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .font(.body)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .foregroundColor(configuration.role == .destructive ? .red : .blue)
            )
            .compositingGroup()
            .overlay(
                VStack {
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.5))
                            .blendMode(.hue)
                    }
                }
            )
            .shadow(radius: configuration.isPressed ? 0 : 5, x: 0, y: configuration.isPressed ? 0 : 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RoundedAndShadowProButtonStyle {
    static var roundedAndShadowPro: RoundedAndShadowProButtonStyle {
        RoundedAndShadowProButtonStyle()
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.filter = .videos // 限制只能选择视频
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // 选择本地视频文件
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func uploadFileToServer(fileURL: URL) {
            // 创建请求
            let uploadURL = URL(string: "http://111.229.183.112:8000/file_upload/upload/")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            
            // 设置请求头
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            // 创建multipart请求体
            var body = Data()
            
//            添加文件数据
            if let fileData = try? Data(contentsOf: fileURL) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"video_file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                body.append(fileData)
                body.append("\r\n".data(using: .utf8)!)
            }else {
                print("无法读取文件数据")
                return
            }

            
            // 结束标记
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // 设置请求体
            request.httpBody = body
            
            // 使用URLSession发起请求
            let session = URLSession.shared
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Upload failed: \(error.localizedDescription)")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("File uploaded successfully")
                    } else {
                        print("Server returned an error: \(httpResponse.statusCode)")
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("Response data: \(responseString)")
                        }
                    }
                }
            }
            
            task.resume()
        }


        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let itemProvider = results.first?.itemProvider else { return }
            
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (url, error) in
                    guard let url = url, error == nil else { return }

                    // 创建一个新的URL，因为原始的URL可能是临时的
                    let fileManager = FileManager.default
                    let newURL = fileManager.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    
                    do {
                        // 如果目标位置已有文件，则删除
                        if fileManager.fileExists(atPath: newURL.path) {
                            try fileManager.removeItem(at: newURL)
                        }
                        try fileManager.copyItem(at: url, to: newURL)
                        
                        DispatchQueue.main.async {
                            self.parent.videoURL = newURL
                            self.uploadFileToServer(fileURL: newURL)
                        }
                    } catch {
                        print("Could not copy file to disk: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}


struct ContentView: View {
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var message = ""
    @State private var showingVideoCapture = false
    @State private var videoURL: URL? = nil
    @State private var showingVideoPicker = false
    
    func fetchMessageFromServer() {
        guard let url = URL(string: "http://111.229.183.112:8000/file_upload/translate/") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET" // 设置为GET请求

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Failed to fetch data")
                return
            }

//            if let fetchedMessage = String(data: data, encoding: .utf8) {
//                DispatchQueue.main.async {
//                    self.message = fetchedMessage
//                }
//            }
            // 尝试将返回的数据转换为字典
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let fetchedMessage = json["translated_text"] as? String {
                    DispatchQueue.main.async {
                        self.message = fetchedMessage
                    }
                } else {
                    print("Failed to decode JSON")
                }
            } catch {
                print("Failed to parse data: \(error.localizedDescription)")
            }
        }

        task.resume()
    }

        
    var body: some View {
        ZStack {
            VStack{
                
                // 视频播放框
                if let videoURL = videoURL {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(minWidth: 0, maxWidth: 250, minHeight: 0, maxHeight: 350)
                        .cornerRadius(8)
                        .shadow(radius: 5)
                } else {
                    // 当没有视频被选中时显示的占位视图
                    Rectangle()
                        .frame(minWidth: 0, maxWidth: 250, minHeight: 0, maxHeight: 350)
                        .foregroundColor(.black)
                        .overlay(
                            Text("选择视频以展示")
                                .foregroundColor(.white)
                        )
                        .cornerRadius(8)
                        .shadow(radius: 5)
                }
                
                Spacer().frame(height: 30)
                
                TextEditor(text: $message)
                    .disabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    .foregroundColor(Color.black)
                    .font(.body)
                    .lineSpacing(5)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding()
                    .frame(minWidth: 0, maxWidth: 350, minHeight: 0, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                
                Spacer().frame(height: 20)
                
//                Button(action: {}, label: { label0 })
//                    .buttonStyle(.roundedAndShadowPro)
                
                Button(action: {
                    fetchMessageFromServer()
                }, label: { label0 })
                .buttonStyle(.roundedAndShadowPro)
                
                Spacer().frame(height: 70)

                HStack(spacing: 10){
                    Button(action: { showingVideoCapture = true }, label: { label1 })
                        .buttonStyle(.roundedAndShadowPro)
                        .sheet(isPresented: $showingVideoCapture) {
                            VideoCaptureView(isPresented: $showingVideoCapture)
                        }
                    
                    Button(action: { showingVideoPicker = true }, label: { label2 })
                        .buttonStyle(.roundedAndShadowPro)
                        .sheet(isPresented: $showingVideoPicker) {
                            VideoPicker(videoURL: $videoURL)
                        }
                }
                
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
    
let label0 = Label("Translation", systemImage: "rectangle.and.pencil.and.ellipsis")
let label1 = Label("Open Camera", systemImage: "camera.circle.fill")
let label2 = Label("Upload Video", systemImage: "square.and.arrow.up.circle.fill")





