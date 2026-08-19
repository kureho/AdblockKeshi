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
        // intrinsicContentSize がテキスト長で伸びると Form の行幅を突き破り
        // 隣の「貼り付け」ボタンを画面外へ押し出すため、横方向は割当幅に従わせる
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

    init(apiClient: ReportAPIClientProtocol,
         historyStore: LocalReportHistoryStore,
         onSubmitSuccess: @escaping (ReportSuccess) -> Void) {
        _viewModel = StateObject(wrappedValue: ReportFormViewModel(
            apiClient: apiClient,
            historyStore: historyStore,
            diagnosticsCollector: ReportDiagnosticsCollector(),
            onSuccess: onSubmitSuccess
        ))
    }

    var body: some View {
        Form {
            // v4.2.0: 報告種別。「広告が消えない」(強める) と「サイトが壊れた」(弱める) は
            // 改善の方向が真逆なので入口で分ける。
            Section {
                Picker("なにを報告しますか？", selection: $viewModel.selectedKind) {
                    ForEach(ReportKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("なにを報告しますか？")
            } footer: {
                Text(viewModel.selectedKind.detail)
                    .font(.caption2)
            }

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
                Text(isBroken ? "問題が起きたページの URL" : "広告が消えなかったページの URL")
            } footer: {
                Text(isBroken ? "表示や操作がおかしかったページを、そのまま貼り付けてください。"
                              : "広告が表示されていたページを、そのまま貼り付けてください。")
                    .font(.caption2)
            }

            Section {
                Picker(seenInQuestionText, selection: $viewModel.selectedSeenIn) {
                    Text("選択してください").tag(SeenIn?.none)
                    ForEach(SeenIn.allCases) { value in
                        Label(value.title, systemImage: value.iconSystemName)
                            .tag(SeenIn?.some(value))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(seenInQuestionText)
            } footer: {
                Text(seenInFooterText)
                    .font(.caption2)
            }

            if !isBroken {
                Section {
                    NavigationLink {
                        AdTypePickerList(selection: $viewModel.selectedAdType)
                    } label: {
                        HStack {
                            Text("広告のタイプ")
                            Spacer()
                            Text(viewModel.selectedAdType?.label ?? "選択してください")
                                .foregroundStyle(viewModel.selectedAdType == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                    }
                } header: {
                    Text("広告のタイプ")
                } footer: {
                    Text("該当するパターンを 1 つ選んでください。当てはまるものが無ければ「その他」を選び、メモ欄に状況を記入してください。")
                        .font(.caption2)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(isBroken ? "例: 記事の画像が表示されない" : "例: 動画上のオーバーレイ",
                              text: $viewModel.memoInput, axis: .vertical)
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
        // メモ欄は複数行 (axis: .vertical) で Return が改行になるため、
        // 「完了」ボタンとスクロール dismiss が無いとキーボードを閉じられず
        // 送信ボタンが押せなくなる
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedField = nil }
            }
        }
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
                primaryButton: .default(Text("お問い合わせ")) {
                    viewModel.dismissError()
                    SupportLink.openContact()
                },
                secondaryButton: .cancel(Text("OK")) { viewModel.dismissError() }
            )
        }
    }

    private var isBroken: Bool { viewModel.selectedKind == .siteBroken }

    private var seenInQuestionText: String {
        isBroken ? "どこで起きましたか？" : "どこで広告を見ましたか？"
    }

    /// 選択中の項目に応じて補足を出し分ける。Safari 以外を選んだ時点で
    /// 「Safari 用フィルタでは消せない」と伝えておく（送信後にも同じ趣旨を出す）。
    private var seenInFooterText: String {
        guard let seenIn = viewModel.selectedSeenIn else {
            return "Safari でウェブページを見ていたのか、他のアプリの中だったのかを選んでください。"
        }
        guard !isBroken else {
            // SeenIn.detail は広告文脈の文（「〜広告が出た」）なので、壊れ報告では言い換える。
            switch seenIn {
            case .safari:   return "Safari でウェブページを見ているときに起きた"
            case .otherApp: return "ゲーム・SNS・動画アプリなど、アプリの中で起きた"
            }
        }
        return seenIn.detail
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

/// `ReportFormView` から push される広告タイプ選択リスト。
/// 各行は「アイコン + 見出し + 補足」の 2 行構成で、視覚的なヒントと
/// 具体例を同時に表示する。
private struct AdTypePickerList: View {
    @Binding var selection: AdType?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(AdType.allCases) { type in
                    Button {
                        selection = type
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: type.iconSystemName)
                                .font(.system(size: 22))
                                .foregroundStyle(.tint)
                                .frame(width: 28, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(type.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if selection == type {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("該当するパターンを 1 つ選んでください。当てはまるものが無ければ「その他」を選び、メモ欄に状況を記入してください。")
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("広告のタイプを選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
