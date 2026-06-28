import { existsSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const CONFIG_DIR = join(homedir(), ".config", "agent-passports")
const SERVER_URL = normalizedServerUrl(
  process.env.AGENT_PASSPORTS_SERVER_URL ||
  readConfigFile("server-url") ||
  "http://127.0.0.1:3284"
)
const MACHINE_TOKEN = process.env.AGENT_PASSPORTS_MACHINE_TOKEN || readConfigFile("machine-token")
const PERMISSION_POLL_INTERVAL_MS = Number(process.env.AGENT_PASSPORTS_PERMISSION_POLL_INTERVAL_MS || 1000)
const PERMISSION_TIMEOUT_MS = Number(process.env.AGENT_PASSPORTS_PERMISSION_TIMEOUT_MS || 120000)

export const AgentPassportsObserver = async ({ directory, worktree, project } = {}) => {
  const seenSessions = new Set()

  return {
    event: async ({ event }) => {
      const sessionID = sessionIdFor(event)
      if (!sessionID) return

      await ensureSessionStarted(sessionID, { event, directory, worktree, project }, seenSessions)
    },

    "permission.ask": async (input, output) => {
      try {
        const response = await postToolRequested(permissionEvent(input, { directory, worktree, project }, seenSessions))
        const immediateDecision = opencodeDecisionFor(response)

        if (immediateDecision) {
          output.status = immediateDecision
          return
        }

        if (response?.status === "asking") {
          output.status = await waitForPermissionDecision(response)
        }
      } catch (error) {
        await logBridgeError("permission.ask", error)
      }
    },

    "tool.execute.before": async (input, output) => {
      try {
        const response = await postToolRequested(toolEvent(input, output, "tool.execute.before", { directory, worktree, project }, seenSessions))
        const immediateDecision = opencodeDecisionFor(response)

        if (immediateDecision === "deny") throw new Error("Agent Identity Control Room denied this tool call")
        if (response?.status === "asking") {
          const decision = await waitForPermissionDecision(response)
          if (decision === "deny") throw new Error("Agent Identity Control Room denied this tool call")
        }
      } catch (error) {
        if (explicitDenial(error)) throw error
        await logBridgeError("tool.execute.before", error)
      }
    },

    "tool.execute.after": async (input, output) => {
      try {
        await ensureSessionStarted(input.sessionID, { event: input, directory, worktree, project }, seenSessions)
        await postOpencodeEvent({
          ...toolEvent(input, output, "tool.execute.after", { directory, worktree, project }, seenSessions),
          type: "tool.finished",
          event_id: eventId(input.sessionID, input.callID, "finished"),
          source_event_id: eventId(input.sessionID, input.callID, "requested"),
          exit_status: exitStatusFor(output),
          action_summary: output?.title || `${input.tool} finished`,
        })
      } catch (error) {
        await logBridgeError("tool.execute.after", error)
      }
    },

    dispose: async () => {
      for (const sessionID of seenSessions) {
        try {
          await postOpencodeEvent({
            type: "session.finished",
            event_id: eventId(sessionID, "session", "finished"),
            session_id: sessionID,
            status: "completed",
            title: sessionTitle({ directory, worktree, project }),
            project_path: projectPath({ directory, worktree, project }),
            pid: process.pid,
          })
        } catch (error) {
          await logBridgeError("dispose", error)
        }
      }
    },
  }
}

async function ensureSessionStarted(sessionID, context, seenSessions) {
  if (!sessionID || seenSessions.has(sessionID)) return

  seenSessions.add(sessionID)
  await postOpencodeEvent({
    type: "session.started",
    event_id: eventId(sessionID, "session", "started"),
    session_id: sessionID,
    title: sessionTitle(context),
    project_path: projectPath(context),
    pid: process.pid,
    canonical_payload: {
      hook: "session",
      event: sanitizedEvent(context.event),
    },
  })
}

async function postToolRequested(payload) {
  await ensureSessionStarted(payload.session_id, { event: payload, directory: payload.project_path }, payload._seenSessions)
  delete payload._seenSessions

  return postOpencodeEvent({
    type: "tool.requested",
    runtime_name: "opencode",
    ...payload,
  })
}

async function postOpencodeEvent(payload) {
  if (!SERVER_URL || !MACHINE_TOKEN) return { ok: false, status: "bridge_unavailable" }

  const response = await fetch(new URL("/opencode/events", SERVER_URL), {
    method: "POST",
    headers: machineHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({
      opencode_event: {
        occurred_at: new Date().toISOString(),
        runtime_name: "opencode",
        pid: process.pid,
        ...payload,
      },
    }),
  })

  if (!response.ok) {
    const body = await response.text()
    throw new Error(`Agent Identity Control Room observer bridge failed: ${response.status} ${body}`)
  }

  return response.json()
}

async function waitForPermissionDecision(initialResponse) {
  const url = permissionRequestUrl(initialResponse)
  if (!url) return "allow"

  const deadline = Date.now() + PERMISSION_TIMEOUT_MS
  while (Date.now() < deadline) {
    const response = await fetchPermissionRequest(url)
    const decision = opencodeDecisionFor(response)
    if (decision) return decision

    await sleep(PERMISSION_POLL_INTERVAL_MS)
  }

  return "deny"
}

async function fetchPermissionRequest(url) {
  const response = await fetch(url, { headers: machineHeaders({ "accept": "application/json" }) })

  if (!response.ok) {
    const body = await response.text()
    throw new Error(`Agent Identity Control Room permission poll failed: ${response.status} ${body}`)
  }

  return response.json()
}

function permissionRequestUrl(response) {
  if (response?.permission_request_url) return response.permission_request_url
  if (response?.permission_request_path) return new URL(response.permission_request_path, SERVER_URL).toString()
  if (response?.permission_request_id) return new URL(`/permission_requests/${response.permission_request_id}`, SERVER_URL).toString()
}

function opencodeDecisionFor(response) {
  if (!response) return undefined
  if (["allowed", "finished"].includes(response.status)) return "allow"
  if (["blocked", "denied"].includes(response.status)) return "deny"
  if (response.status === "resolved" && ["allow_once", "passport_grant"].includes(response.decision)) return "allow"
  if (response.status === "resolved" && response.decision === "deny") return "deny"
}

function toolEvent(input, output, hook, context, seenSessions) {
  const args = output?.args || input.args
  const actionText = summarizeArgs(args)
  const capability = capabilityFor(input.tool)
  const sessionID = sessionIdFor(input)

  return {
    _seenSessions: seenSessions,
    session_id: sessionID,
    event_id: eventId(sessionID, input.callID, "requested"),
    actor_ref: actorRef(input),
    actor_name: actorName(input),
    parent_actor_ref: parentActorRef(input),
    title: sessionTitle(context),
    project_path: projectPath(context),
    capability,
    action_kind: input.tool,
    action_summary: `${input.tool}: ${actionText}`,
    command: commandFor(input.tool, args),
    path: pathFor(args),
    canonical_payload: { hook, tool: input.tool, args: sanitizedEvent(args) },
    risk_level: riskLevelFor(capability),
    risk_summary: riskSummaryFor(capability, actionText),
    suggested_capability: capability,
    suggested_pattern: suggestedPatternFor(input.tool, args, actionText),
  }
}

function permissionEvent(input, context, seenSessions) {
  const text = Array.isArray(input.pattern) ? input.pattern.join(" ") : input.pattern || input.title
  const capability = capabilityFor(input.type)
  const callID = input.callID || input.id
  const sessionID = sessionIdFor(input)

  return {
    _seenSessions: seenSessions,
    session_id: sessionID,
    event_id: eventId(sessionID, callID, "requested"),
    actor_ref: actorRef(input),
    actor_name: actorName(input),
    parent_actor_ref: parentActorRef(input),
    title: sessionTitle(context),
    project_path: projectPath(context),
    capability,
    action_kind: input.type,
    action_summary: input.title || `${input.type}: ${text}`,
    command: input.type === "bash" ? text : undefined,
    path: pathFromPattern(text),
    canonical_payload: { hook: "permission.ask", permission: sanitizedEvent(input) },
    risk_level: riskLevelFor(capability),
    risk_summary: riskSummaryFor(capability, text),
    suggested_capability: capability,
    suggested_pattern: text,
  }
}

function sessionIdFor(input = {}) {
  return stringValue(input.sessionID) ||
    stringValue(input.sessionId) ||
    stringValue(input.session_id) ||
    stringValue(input.session?.id) ||
    stringValue(input.properties?.sessionID) ||
    stringValue(input.properties?.session_id)
}

function eventId(sessionID, callID, suffix) {
  return `opencode-observed-${sessionID || "unknown"}-${callID || "unknown"}-${suffix}`
}

function actorRef(input) {
  return stringValue(input.agent) ||
    stringValue(input.agentID) ||
    stringValue(input.agentId) ||
    stringValue(input.actor) ||
    stringValue(input.actor_ref) ||
    stringValue(input.actorRef) ||
    stringValue(input.session?.agent) ||
    "main-agent"
}

function actorName(input) {
  const value = input.agent || input.actor || input.session?.agent
  if (typeof value === "object" && value) return value.name || value.id || value.ref
  return actorRef(input)
}

function parentActorRef(input) {
  return stringValue(input.parentAgent) ||
    stringValue(input.parentAgentID) ||
    stringValue(input.parent_agent_ref) ||
    (actorRef(input) === "main-agent" ? "local-owner" : "main-agent")
}

function stringValue(value) {
  if (!value) return undefined
  if (typeof value === "string") return value
  if (typeof value === "object") return value.id || value.name || value.ref
}

function capabilityFor(tool) {
  if (["bash", "shell"].includes(tool)) return "bash"
  if (["edit", "write", "patch"].includes(tool)) return "edit"
  if (["webfetch", "websearch", "fetch"].includes(tool)) return "web"
  if (["task", "subtask"].includes(tool)) return "delegate"
  return "read"
}

function summarizeArgs(args) {
  if (!args || typeof args !== "object") return String(args || "")
  return args.command || args.filePath || args.path || args.pattern || JSON.stringify(args)
}

function commandFor(tool, args) {
  return capabilityFor(tool) === "bash" ? summarizeArgs(args) : undefined
}

function pathFor(args) {
  if (!args || typeof args !== "object") return undefined
  return args.filePath || args.path || pathFromPattern(args.pattern)
}

function pathFromPattern(pattern) {
  if (!pattern || typeof pattern !== "string") return undefined
  return pattern.includes("/") || pattern.includes(".") ? pattern : undefined
}

function suggestedPatternFor(tool, args, fallback) {
  return commandFor(tool, args) || pathFor(args) || fallback
}

function riskLevelFor(capability) {
  if (capability === "web") return "high"
  if (["bash", "edit", "delegate"].includes(capability)) return "medium"
  return "low"
}

function riskSummaryFor(capability, text) {
  const subject = text || "runtime action"
  if (capability === "bash") return `Runs a local command: ${subject}`
  if (capability === "edit") return `May change local project files: ${subject}`
  if (capability === "web") return `May access the network: ${subject}`
  if (capability === "delegate") return `May delegate work to another agent: ${subject}`
  return `Reads local project context: ${subject}`
}

function exitStatusFor(output) {
  if (typeof output?.exitCode === "number") return output.exitCode
  if (typeof output?.exit_status === "number") return output.exit_status
  if (typeof output?.code === "number") return output.code
  return 0
}

function projectPath({ directory, worktree, event } = {}) {
  return worktree || directory || event?.project_path || event?.directory || process.cwd()
}

function sessionTitle(context = {}) {
  return context.project?.name || basename(projectPath(context)) || "opencode session"
}

function basename(path) {
  return String(path || "").split("/").filter(Boolean).at(-1)
}

function sanitizedEvent(value) {
  if (!value || typeof value !== "object") return value
  return JSON.parse(JSON.stringify(value, (key, inner) => {
    if (/key|token|secret|password|authorization|cookie|credential|api/i.test(key)) return "[redacted]"
    return inner
  }))
}

function machineHeaders(headers = {}) {
  return {
    ...headers,
    "x-agent-passports-machine-token": MACHINE_TOKEN,
  }
}

function readConfigFile(name) {
  const path = join(CONFIG_DIR, name)
  return existsSync(path) ? readFileSync(path, "utf8").trim() : undefined
}

function normalizedServerUrl(value) {
  if (!value) return undefined
  return value.endsWith("/") ? value.slice(0, -1) : value
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function explicitDenial(error) {
  return String(error?.message || "").includes("Agent Identity Control Room denied")
}

async function logBridgeError(hook, error) {
  if (process.env.AGENT_PASSPORTS_DEBUG) {
    console.error(`Agent Identity Control Room observer ${hook} failed open:`, error)
  }
}
