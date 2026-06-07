import SwiftUI

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
                        TextField("https://example.com/...", text: $viewModel.urlInput)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
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
