import SwiftUI

struct ToolPartView: View {
    let part: ToolPart
    let viewModel: ChatViewModel
    @State private var isExpanded = false
    @State private var showFullOutput = false
    @State private var localAnswers: [[String]] = []
    @State private var customInputs: [String] = []
    @State private var isSubmitting: Bool = false

    private var badgeStatus: ConnectionStatus {
        switch part.state.status {
        case .pending: return .idle
        case .running: return .connecting
        case .completed: return .active
        case .error: return .error
        }
    }

    private var inputDict: [String: AnyCodable] {
        switch part.state {
        case .pending(let s): return s.input ?? [:]
        case .running(let s): return s.input ?? [:]
        case .completed(let s): return s.input ?? [:]
        case .error(let s): return s.input ?? [:]
        }
    }

    private var questionRequest: QuestionRequest? {
        viewModel.questionRequest(for: part)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                    Text(part.tool)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.cloud)
                        .lineLimit(1)
                    Spacer()
                    StatusBadge(status: badgeStatus)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(Theme.Colors.hairline)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    // Input section
                    inputSection

                    // Output/Error section
                    outputSection
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.graphite)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
        .onAppear {
            if questionRequest != nil {
                isExpanded = true
                syncQuestionState()
            }
        }
        .onChange(of: questionRequest?.id) { _, _ in
            if questionRequest != nil {
                isExpanded = true
                syncQuestionState()
            }
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INPUT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.Colors.silver)
                .tracking(1)

            if let request = questionRequest {
                questionSection(request)
            } else {
                let inputText: String = {
                    if inputDict.isEmpty { return "(no input)" }
                    return inputDict
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key): \(describeValue($0.value.value))" }
                        .joined(separator: "\n")
                }()

                Text(inputText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.silver)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.carbon)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        switch part.state {
        case .completed(let s):
            VStack(alignment: .leading, spacing: 4) {
                Text("OUTPUT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Colors.silver)
                    .tracking(1)

                let outputText = s.output ?? ""
                let isTruncated = outputText.count > 1500
                let displayText = showFullOutput ? outputText : String(outputText.prefix(1500)) + (isTruncated ? "…" : "")

                Text(displayText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neonGreen)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.carbon)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if isTruncated && !showFullOutput {
                    Button("Show full output") {
                        showFullOutput = true
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        case .error(let s):
            VStack(alignment: .leading, spacing: 4) {
                Text("ERROR")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Colors.hotPink)
                    .tracking(1)

                Text(s.error)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.hotPink)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.carbon)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case .running(let s):
            HStack(spacing: 6) {
                ProgressView()
                    .tint(Theme.Colors.neonOrange)
                    .scaleEffect(0.7)
                Text(s.title ?? "Running…")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.silver)
            }
        case .pending:
            EmptyView()
        }
    }

    private func describeValue(_ v: AnyCodableValue) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return s
        case .array(let arr): return "[\(arr.count) items]"
        case .object(let obj): return "{\(obj.count) keys}"
        }
    }

    // MARK: - Question UI

    @ViewBuilder
    private func questionSection(_ request: QuestionRequest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.neonOrange)
                Text("Needs your input")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.cloud)
                Spacer()
            }

            ForEach(request.questions.indices, id: \.self) { index in
                let info = request.questions[index]
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.header)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.cloud)
                    Text(info.question)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(info.options, id: \.self) { option in
                            optionRow(option, questionIndex: index, allowsMultiple: info.allowsMultiple)
                        }
                    }

                    if info.allowsCustom {
                        TextField("Type your answer…", text: bindingForCustomInput(index))
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.cloud)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .background(Theme.Colors.carbon)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.carbon)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button("Reject") {
                    submitQuestionReply(request, allow: false)
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.hotPink)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.hotPink.opacity(0.15))
                )
                .disabled(isSubmitting)

                Button(isSubmitting ? "Sending…" : "Send") {
                    submitQuestionReply(request, allow: true)
                }
                .font(.caption.bold())
                .foregroundStyle(Theme.Colors.cyberBlue)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.cyberBlue.opacity(0.15))
                )
                .disabled(isSubmitting || !canSubmitAnswers(for: request))
            }
        }
    }

    private func optionRow(_ option: QuestionOption, questionIndex: Int, allowsMultiple: Bool) -> some View {
        let isSelected = localAnswers.indices.contains(questionIndex)
            ? localAnswers[questionIndex].contains(option.label)
            : false

        return Button {
            toggleOption(option.label, for: questionIndex, allowsMultiple: allowsMultiple)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Theme.Colors.neonGreen : Theme.Colors.silver)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.cloud)
                    Text(option.description)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.smoke)
                }
                Spacer()
            }
            .padding(8)
            .background(Theme.Colors.graphite.opacity(isSelected ? 0.6 : 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func toggleOption(_ label: String, for index: Int, allowsMultiple: Bool) {
        guard localAnswers.indices.contains(index) else { return }
        if allowsMultiple {
            if let existingIndex = localAnswers[index].firstIndex(of: label) {
                localAnswers[index].remove(at: existingIndex)
            } else {
                localAnswers[index].append(label)
            }
        } else {
            if localAnswers[index].contains(label) {
                localAnswers[index] = []
            } else {
                localAnswers[index] = [label]
            }
        }
    }

    private func bindingForCustomInput(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard customInputs.indices.contains(index) else { return "" }
                return customInputs[index]
            },
            set: { value in
                guard customInputs.indices.contains(index) else { return }
                customInputs[index] = value
            }
        )
    }

    private func syncQuestionState() {
        guard let request = questionRequest else { return }
        if localAnswers.count != request.questions.count {
            localAnswers = Array(repeating: [], count: request.questions.count)
        }
        if customInputs.count != request.questions.count {
            customInputs = Array(repeating: "", count: request.questions.count)
        }
    }

    private func canSubmitAnswers(for request: QuestionRequest) -> Bool {
        for index in request.questions.indices {
            let selections = localAnswers.indices.contains(index) ? localAnswers[index] : []
            let custom = customInputs.indices.contains(index) ? customInputs[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if selections.isEmpty && custom.isEmpty {
                return false
            }
        }
        return true
    }

    private func buildAnswers(for request: QuestionRequest) -> [QuestionAnswer] {
        request.questions.indices.map { index in
            var answers = localAnswers.indices.contains(index) ? localAnswers[index] : []
            let custom = customInputs.indices.contains(index) ? customInputs[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if !custom.isEmpty {
                if !answers.contains(custom) {
                    answers.append(custom)
                }
            }
            return answers
        }
    }

    private func submitQuestionReply(_ request: QuestionRequest, allow: Bool) {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                if allow {
                    let answers = buildAnswers(for: request)
                    try await viewModel.replyToQuestion(request, answers: answers)
                } else {
                    try await viewModel.rejectQuestion(request)
                }
            } catch {
                viewModel.error = error.localizedDescription
            }
        }
    }
}
