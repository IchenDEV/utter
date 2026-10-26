#!/usr/bin/env python3
"""Run actual review/control sources with dependency-free synthetic boundaries."""
import subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[4]
stubs='''import Foundation
 enum SessionExecutionPhase { case processing, delivering }
 enum SessionStage { case processing }
 enum IntegrationError: Error { case invalidSessionState }
 enum DeliveryError: Error { case invalidTarget }
 @MainActor protocol SessionJobControl: AnyObject { var isCurrent: Bool { get }; func waitForSelectionEditDecision(_ p: SelectionEditProposal) async throws }
 @MainActor class SessionTiming { func begin(_ s: SessionStage)->UUID { UUID() }; func end(_ id: UUID) {} }
 @MainActor protocol OutputTargetLease: AnyObject { var id: UUID { get }; var processIdentifier: Int32 { get }; var selectedText: String? { get }; var isCurrent: Bool { get } }
 @MainActor final class Target: OutputTargetLease { let id=UUID();let processIdentifier:Int32=12;var selectedText:String?="家👨‍👩‍👧‍👦é\\n原文";var isCurrent=true }
 @MainActor final class Recording { var stopped=false;var closed=false;func stopCapture() async { stopped=true };func close() async { closed=true } }
 @MainActor final class Engine { func cancelListening() {};func drainRecognition() async {} }
 @MainActor final class Callbacks { func drain() async {} }
 struct Intent { let id=UUID() }
 @MainActor final class VoiceSessionJob { let intent=Intent();var recording:Recording?;var engine:Engine?;let callbacks=Callbacks();func check(_ c:any SessionJobControl) throws { try Task.checkCancellation();if !c.isCurrent { throw CancellationError() } } }
'''
runner='''
@main struct Check {
 @MainActor static func main() async throws {
  for action in ["apply","cancel","stale","empty","expired","replaced"] {
   let job=VoiceSessionJob();let target=Target();let original=target.selectedText!;let recording=Recording();job.recording=recording
   var control:SessionControl!;var current=true;var writes=0
   control=SessionControl(isCurrent:{ current },cancel:{ control.revoke() },update:{ _,_ in })
   let task=Task { @MainActor in try await job.reviewSelectionEdit(action=="empty" ? " " : "新👩🏽‍💻文",instruction:"改简短",target:target,control:control);writes += 1 }
   if action=="empty" { do { try await task.value;fatalError("empty accepted") } catch {};precondition(writes==0);continue }
   for _ in 0..<1000 { if control.selectionEditProposal != nil { break };await Task.yield() }
   let proposal=control.selectionEditProposal!;precondition(proposal.originalSelection==original && proposal.recognizedInstruction=="改简短" && writes==0 && recording.stopped && recording.closed)
   precondition(!control.applySelectionEdit(UUID()))
   if action=="cancel" { control.revoke() }
   else if action=="replaced" { current=false;precondition(!control.applySelectionEdit(proposal.id));control.revoke() }
   else { if action=="stale" { target.isCurrent=false };precondition(control.applySelectionEdit(proposal.id));precondition(!control.applySelectionEdit(proposal.id)) }
   do { try await task.value;precondition(action=="apply" || action=="expired") } catch { precondition(action=="cancel" || action=="stale" || action=="replaced") }
   precondition(writes == ((action=="apply" || action=="expired") ? 1 : 0));precondition(target.selectedText==original)
  }
  var control:SessionControl!;control=SessionControl(isCurrent:{true},cancel:{control.revoke()},update:{_,_ in})
  let expired=SelectionEditProposal(sessionID:UUID(),targetID:UUID(),processIdentifier:12,originalSelection:"a",recognizedInstruction:"b",candidate:"c",expiresAt:Date().addingTimeInterval(-1))
  do { try await control.waitForSelectionEditDecision(expired);fatalError("expired accepted") } catch {}
  let expiring=SelectionEditProposal(sessionID:UUID(),targetID:UUID(),processIdentifier:12,originalSelection:"a",recognizedInstruction:"b",candidate:"c",expiresAt:Date().addingTimeInterval(0.02))
  do { try await control.waitForSelectionEditDecision(expiring);fatalError("timeout accepted") } catch {}
  precondition(control.selectionEditProposal==nil)
  print("PASS: actual review/control pending, exact Unicode, microphone drain, apply once, cancel, stale, replaced, empty, expiry")
 }
}
'''
sources=[]
for f in ['Sources/UtterContracts/SelectionEditProposal.swift','Sources/UtterSession/SessionControl.swift','Sources/UtterSession/Native/VoiceSessionJob+Review.swift']:
 s=(root/f).read_text();s='\n'.join(l for l in s.splitlines() if not l.startswith('import Utter'));s=s.replace('package ','');sources.append(s)
with tempfile.TemporaryDirectory(prefix='utter-review-') as d:
 p=Path(d);(p/'check.swift').write_text(stubs+'\n'.join(sources)+runner)
 subprocess.run(['swiftc','-parse-as-library','-swift-version','5',str(p/'check.swift'),'-o',str(p/'check')],check=True,timeout=15)
 subprocess.run([str(p/'check')],check=True,timeout=5)
