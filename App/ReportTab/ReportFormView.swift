import SwiftUI
import UIKit

/// SwiftUI TextField applies iOS's URL data-detector heuristics to the
/// placeholder when keyboardType(.URL) is set, which renders the prompt
/// "https://example.com/..." in accent blue and ignores foregroundStyle()
/// hints. This wrapper drops down to UITextField so we can control the
/// placeholder color explicitly via attributedPlaceholder.
private struct URLTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.keyboardType = .URL
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        tf.returnKeyType = .done
        tf.clearButtonMode = .whileEditing
        tf.font = UIFont.preferredFont(forTextStyle: .body)
        tf.adjustsFontForContentSizeCategory = true
        tf.textColor = UIColor.label
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: URLTextField
        init(_ parent: URLTextField) { self.parent = parent }
        @objc func editingChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit()
            return true
        }
    }
}

struct ReportFormView: View {
    @StateObject private var viewModel: ReportFormViewModel
    @FocusState private var focusedField: Field?

    enum Field { case url, memo }

    init(apiClient: ReportAPIClientProtocol, onSubmitSuccess: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ReportFormViewModel(apiClient: apiClient, onSuccess: onSubmitSuccess))
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        URLTextField(
                            text: $viewModel.urlInput,
                            placeholder: "https://example.com/...",
                            onCommit: { focusedField = nil }
                        )
                            .focused($focusedField, equals: .url)
                        Button("貼り付け") {
                            if let s = UIPasteboard.general.string {
                                viewModel.urlInput = s
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let err = viewModel.urlError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("広告があった URL")
            } footer: {
                Text("Safari のアドレスバーからコピーして貼り付けてください")
                    .font(.caption2)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("例: 動画上のオーバーレイ", text: $viewModel.memoInput, axis: .vertical)
                        .lineLimit(5, reservesSpace: true)
                        .focused($focusedField, equals: .memo)
                    HStack {
                        if let err = viewModel.memoError {
                            Text(err).font(.caption2).foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(viewModel.memoCharCount) / \(MemoValidator.maxLength)")
                            .font(.caption2)
                            .foregroundStyle(viewModel.memoCharRemaining < 20 ? .orange : .secondary)
                    }
                }
            } header: {
                Text("メモ (任意)")
            } footer: {
                Text("URL は記述しないでください (上の欄に入れてください)")
                    .font(.caption2)
            }

            Section {
                Button {
                    focusedField = nil
                    viewModel.beginSubmit()
                } label: {
                    HStack {
                        if case .submitting = viewModel.state {
                            ProgressView().controlSize(.small)
                            Text("送信中…").padding(.leading, 6)
                        } else if case .awaitingTurnstile = viewModel.state {
                            ProgressView().controlSize(.small)
                            Text("確認中…").padding(.leading, 6)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("送信").padding(.leading, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSubmit)
            }
        }
        .navigationTitle("報告")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: turnstileBinding) {
            TurnstileChallengeSheet { result in
                switch result {
                case .success(let token):
                    Task { await viewModel.completeSubmit(turnstileResponse: token) }
                case .failure:
                    viewModel.cancelTurnstile()
                }
            }
        }
        .alert(isPresented: errorBinding) {
            Alert(
                title: Text("送信に失敗しました"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK")) { viewModel.dismissError() }
            )
        }
    }

    private var turnstileBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showsTurnstileSheet },
            set: { if !$0 { viewModel.cancelTurnstile() } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { if case .error = viewModel.state { return true }; return false },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var errorMessage: String {
        if case .error(let err) = viewModel.state {
            return err.localizedDescription
        }
        return ""
    }
}
