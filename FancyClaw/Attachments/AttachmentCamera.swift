import SwiftUI
import UIKit

/// The camera capture UI has no native SwiftUI equivalent.
struct AttachmentCamera: UIViewControllerRepresentable {
    let completion: (Result<Data, Error>?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Result<Data, Error>?) -> Void
        init(completion: @escaping (Result<Data, Error>?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1) {
                completion(.success(data))
            } else { completion(.failure(CocoaError(.fileReadCorruptFile))) }
        }
    }
}
