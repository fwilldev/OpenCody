//
//  AgentModelPicker.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

struct AgentModelPicker: View {
    let viewModel: ChatViewModel
    let connectionManager: ConnectionManager

    @State private var showSheet = false
    @State private var agents: [Agent] = []
    @State private var providers: [Provider] = []
    @State private var connectedProviderIDs: [String] = []
    @State private var expandedProviderID: String? = nil

    private var agentLabel: String {
        viewModel.selectedAgentID ?? "Default Agent"
    }

    private var modelLabel: String {
        if let pid = viewModel.selectedProviderID, let mid = viewModel.selectedModelID {
            return "\(pid) / \(mid)"
        }
        return "Default Model"
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.electricPurple)

                Text(agentLabel)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(Theme.Colors.silver)
                    .font(.caption)

                Text(modelLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.silver)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.silver)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.Colors.graphite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.Colors.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            pickerSheet
                .presentationBackground(Theme.Colors.carbon)
                .presentationDetents([.medium, .large])
                .task {
                    await loadAgentsAndProviders()
                }
        }
        .task {
            await loadAgentsAndProviders()
        }
    }

    // MARK: - Picker Sheet

    @ViewBuilder
    private var pickerSheet: some View {
        NavigationStack {
            List {
                // MARK: Agent Section
                Section("Agent") {
                    // Default option
                    Button {
                        viewModel.selectedAgentID = nil
                    } label: {
                        HStack {
                            Text("Default Agent")
                                .foregroundStyle(Theme.Colors.cloud)
                            Spacer()
                            if viewModel.selectedAgentID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.cyberBlue)
                                    .font(.subheadline.bold())
                            }
                        }
                    }
                    .listRowBackground(Theme.Colors.graphite)

                    ForEach(agents.filter { !($0.hidden ?? false) }, id: \.name) { agent in
                        Button {
                            viewModel.selectedAgentID = agent.name
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .foregroundStyle(Theme.Colors.cloud)
                                    if let desc = agent.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.silver)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if viewModel.selectedAgentID == agent.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.cyberBlue)
                                        .font(.subheadline.bold())
                                }
                            }
                        }
                        .listRowBackground(Theme.Colors.graphite)
                    }
                }

                // MARK: Provider & Model Section
                let connectedProviders = providers.filter { connectedProviderIDs.contains($0.id) }
                if !connectedProviders.isEmpty {
                    Section("Provider & Model") {
                        ForEach(connectedProviders) { provider in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedProviderID == provider.id },
                                    set: { isExpanded in
                                        expandedProviderID = isExpanded ? provider.id : nil
                                    }
                                )
                            ) {
                                // Models within this provider
                                let sortedModels = provider.models.values.sorted { $0.name < $1.name }
                                ForEach(sortedModels) { model in
                                    Button {
                                        viewModel.selectedProviderID = provider.id
                                        viewModel.selectedModelID = model.id
                                        showSheet = false
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(model.name)
                                                    .font(.subheadline)
                                                    .foregroundStyle(Theme.Colors.cloud)
                                                Text(model.id)
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.Colors.silver)
                                            }
                                            Spacer()
                                            if viewModel.selectedProviderID == provider.id
                                                && viewModel.selectedModelID == model.id {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Theme.Colors.cyberBlue)
                                                    .font(.subheadline.bold())
                                            }
                                        }
                                    }
                                    .listRowBackground(Theme.Colors.slate)
                                }
                            } label: {
                                HStack {
                                    Text(provider.name)
                                        .foregroundStyle(Theme.Colors.cloud)
                                    Spacer()
                                    if viewModel.selectedProviderID == provider.id {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundStyle(Theme.Colors.cyberBlue)
                                    }
                                }
                            }
                            .listRowBackground(Theme.Colors.graphite)
                        }
                    }
                } else if providers.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Theme.Colors.cyberBlue)
                            Spacer()
                        }
                        .listRowBackground(Theme.Colors.graphite)
                    }
                } else {
                    Section("Provider & Model") {
                        Text("No connected providers")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.silver)
                            .listRowBackground(Theme.Colors.graphite)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.carbon)
            .navigationTitle("Agent & Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { showSheet = false }
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadAgentsAndProviders() async {
        guard let client = connectionManager.activeAPIClient else { return }

        async let agentFetch = AgentAPI(client: client).list()
        async let providerFetch = ProviderAPI(client: client).list()

        agents = (try? await agentFetch) ?? []
        let response = (try? await providerFetch) ?? ProviderAPI.ProviderListResponse(all: [], default: [:], connected: [])
        providers = response.all
        connectedProviderIDs = response.connected
    }
}
