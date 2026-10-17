
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "inf": {
          Tables: {
            "agencies": {
                  Row: {
                    "created_at": string,"created_by": string | null,"email": string | null,"gstin": string | null,"id": string,"legal_name": string | null,"name": string,"notes": string | null,"phone_e164": string | null,"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"email"?: string | null,"gstin"?: string | null,"id"?: string,"legal_name"?: string | null,"name": string,"notes"?: string | null,"phone_e164"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"email"?: string | null,"gstin"?: string | null,"id"?: string,"legal_name"?: string | null,"name"?: string,"notes"?: string | null,"phone_e164"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"agency_creator_links": {
                  Row: {
                    "agency_id": string,"can_act_deliverables": boolean,"can_negotiate_sign": boolean,"can_view": boolean,"can_view_earnings": boolean,"creator_id": string,"id": string,"requested_at": string,"requested_by": string | null,"responded_at": string | null,"revoked_at": string | null,"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agency_id": string,"can_act_deliverables"?: boolean,"can_negotiate_sign"?: boolean,"can_view"?: boolean,"can_view_earnings"?: boolean,"creator_id": string,"id"?: string,"requested_at"?: string,"requested_by"?: string | null,"responded_at"?: string | null,"revoked_at"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "agency_id"?: string,"can_act_deliverables"?: boolean,"can_negotiate_sign"?: boolean,"can_view"?: boolean,"can_view_earnings"?: boolean,"creator_id"?: string,"id"?: string,"requested_at"?: string,"requested_by"?: string | null,"responded_at"?: string | null,"revoked_at"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "agency_creator_links_agency_id_fkey"
      columns: ["agency_id"]
isOneToOne: false
      referencedRelation: "agencies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agency_creator_links_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"agency_members": {
                  Row: {
                    "agency_id": string,"created_at": string,"email": string,"full_name": string,"id": string,"invited_by": string | null,"linked_at": string | null,"role": string,"status": string,"user_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "agency_id": string,"created_at"?: string,"email": string,"full_name": string,"id"?: string,"invited_by"?: string | null,"linked_at"?: string | null,"role"?: string,"status"?: string,"user_id"?: string | null
                  }
                  Update: {
                    "agency_id"?: string,"created_at"?: string,"email"?: string,"full_name"?: string,"id"?: string,"invited_by"?: string | null,"linked_at"?: string | null,"role"?: string,"status"?: string,"user_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "agency_members_agency_id_fkey"
      columns: ["agency_id"]
isOneToOne: false
      referencedRelation: "agencies"
      referencedColumns: ["id"]
    }
                  ]
                },"announcements": {
                  Row: {
                    "body": string,"channels": (string)[],"created_at": string,"created_by": string,"id": string,"link": string | null,"recipients": number | null,"scheduled_at": string | null,"segment": NonNullable<Json>,"sent_at": string | null,"status": string,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "body": string,"channels"?: (string)[],"created_at"?: string,"created_by"?: string,"id"?: string,"link"?: string | null,"recipients"?: number | null,"scheduled_at"?: string | null,"segment"?: NonNullable<Json>,"sent_at"?: string | null,"status"?: string,"title": string,"updated_at"?: string
                  }
                  Update: {
                    "body"?: string,"channels"?: (string)[],"created_at"?: string,"created_by"?: string,"id"?: string,"link"?: string | null,"recipients"?: number | null,"scheduled_at"?: string | null,"segment"?: NonNullable<Json>,"sent_at"?: string | null,"status"?: string,"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"application_offers": {
                  Row: {
                    "application_id": string,"created_at": string,"created_by": string,"from_side": string,"id": string,"message": string | null,"status": string,"terms": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "application_id": string,"created_at"?: string,"created_by"?: string,"from_side": string,"id"?: string,"message"?: string | null,"status"?: string,"terms": NonNullable<Json>
                  }
                  Update: {
                    "application_id"?: string,"created_at"?: string,"created_by"?: string,"from_side"?: string,"id"?: string,"message"?: string | null,"status"?: string,"terms"?: NonNullable<Json>
                  }
                  Relationships: [
                    {
      foreignKeyName: "application_offers_application_id_fkey"
      columns: ["application_id"]
isOneToOne: false
      referencedRelation: "campaign_applications"
      referencedColumns: ["id"]
    }
                  ]
                },"attribution_decisions": {
                  Row: {
                    "actor": string,"actor_id": string | null,"at": string,"attribution_id": string,"from_status": string | null,"id": number,"reason": string | null,"to_status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actor": string,"actor_id"?: string | null,"at"?: string,"attribution_id": string,"from_status"?: string | null,"id"?: never,"reason"?: string | null,"to_status": string
                  }
                  Update: {
                    "actor"?: string,"actor_id"?: string | null,"at"?: string,"attribution_id"?: string,"from_status"?: string | null,"id"?: never,"reason"?: string | null,"to_status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "attribution_decisions_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "attribution_decisions_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads_live"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "attribution_decisions_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_revenue"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "attribution_decisions_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "lead_attributions"
      referencedColumns: ["id"]
    }
                  ]
                },"audit_log": {
                  Row: {
                    "action": string,"actor_id": string | null,"actor_role": string | null,"after": Json | null,"at": string,"before": Json | null,"entity_id": string | null,"entity_type": string,"id": number,"ip": unknown,"request_id": string | null,"user_agent": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_id"?: string | null,"actor_role"?: string | null,"after"?: Json | null,"at"?: string,"before"?: Json | null,"entity_id"?: string | null,"entity_type": string,"id"?: never,"ip"?: unknown,"request_id"?: string | null,"user_agent"?: string | null
                  }
                  Update: {
                    "action"?: string,"actor_id"?: string | null,"actor_role"?: string | null,"after"?: Json | null,"at"?: string,"before"?: Json | null,"entity_id"?: string | null,"entity_type"?: string,"id"?: never,"ip"?: unknown,"request_id"?: string | null,"user_agent"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"banned_claims": {
                  Row: {
                    "active": boolean,"created_at": string,"created_by": string | null,"id": string,"kind": string,"note": string | null,"pattern": string,"severity": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"created_by"?: string | null,"id"?: string,"kind"?: string,"note"?: string | null,"pattern": string,"severity"?: string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"created_by"?: string | null,"id"?: string,"kind"?: string,"note"?: string | null,"pattern"?: string,"severity"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"brief_acknowledgements": {
                  Row: {
                    "acknowledged_at": string,"brief_id": string,"id": number,"side": string,"user_id": string,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "acknowledged_at"?: string,"brief_id": string,"id"?: never,"side": string,"user_id"?: string,"version_id": string
                  }
                  Update: {
                    "acknowledged_at"?: string,"brief_id"?: string,"id"?: never,"side"?: string,"user_id"?: string,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "brief_acknowledgements_brief_id_fkey"
      columns: ["brief_id"]
isOneToOne: false
      referencedRelation: "briefs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "brief_acknowledgements_version_id_fkey"
      columns: ["version_id"]
isOneToOne: true
      referencedRelation: "brief_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"brief_questions": {
                  Row: {
                    "author_id": string,"author_side": string,"body": string,"brief_id": string,"created_at": string,"id": string,"parent_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id"?: string,"author_side": string,"body": string,"brief_id": string,"created_at"?: string,"id"?: string,"parent_id"?: string | null
                  }
                  Update: {
                    "author_id"?: string,"author_side"?: string,"body"?: string,"brief_id"?: string,"created_at"?: string,"id"?: string,"parent_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "brief_questions_brief_id_fkey"
      columns: ["brief_id"]
isOneToOne: false
      referencedRelation: "briefs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "brief_questions_parent_id_fkey"
      columns: ["parent_id"]
isOneToOne: false
      referencedRelation: "brief_questions"
      referencedColumns: ["id"]
    }
                  ]
                },"brief_templates": {
                  Row: {
                    "archived_at": string | null,"content": NonNullable<Json>,"created_at": string,"created_by": string | null,"description": string | null,"id": string,"is_default": boolean,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"content"?: NonNullable<Json>,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"id"?: string,"is_default"?: boolean,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "archived_at"?: string | null,"content"?: NonNullable<Json>,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"id"?: string,"is_default"?: boolean,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"brief_versions": {
                  Row: {
                    "brief_id": string,"content": NonNullable<Json>,"id": string,"note": string | null,"published_at": string,"published_by": string | null,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "brief_id": string,"content": NonNullable<Json>,"id"?: string,"note"?: string | null,"published_at"?: string,"published_by"?: string | null,"version": number
                  }
                  Update: {
                    "brief_id"?: string,"content"?: NonNullable<Json>,"id"?: string,"note"?: string | null,"published_at"?: string,"published_by"?: string | null,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "brief_versions_brief_id_fkey"
      columns: ["brief_id"]
isOneToOne: false
      referencedRelation: "briefs"
      referencedColumns: ["id"]
    }
                  ]
                },"briefs": {
                  Row: {
                    "created_at": string,"created_by": string | null,"current_version_id": string | null,"deal_id": string,"draft_content": NonNullable<Json>,"id": string,"template_id": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"current_version_id"?: string | null,"deal_id": string,"draft_content"?: NonNullable<Json>,"id"?: string,"template_id"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"current_version_id"?: string | null,"deal_id"?: string,"draft_content"?: NonNullable<Json>,"id"?: string,"template_id"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "briefs_current_version_fk"
      columns: ["current_version_id"]
isOneToOne: false
      referencedRelation: "brief_versions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "briefs_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: true
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "briefs_template_id_fkey"
      columns: ["template_id"]
isOneToOne: false
      referencedRelation: "brief_templates"
      referencedColumns: ["id"]
    }
                  ]
                },"campaign_applications": {
                  Row: {
                    "accepted_terms": Json | null,"campaign_id": string,"created_at": string,"creator_id": string,"decided_at": string | null,"decided_by": string | null,"id": string,"pitch": string | null,"rejection_reason": string | null,"sample_links": (string)[],"source": string,"status": string,"submitted_by": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accepted_terms"?: Json | null,"campaign_id": string,"created_at"?: string,"creator_id": string,"decided_at"?: string | null,"decided_by"?: string | null,"id"?: string,"pitch"?: string | null,"rejection_reason"?: string | null,"sample_links"?: (string)[],"source"?: string,"status"?: string,"submitted_by"?: string,"updated_at"?: string
                  }
                  Update: {
                    "accepted_terms"?: Json | null,"campaign_id"?: string,"created_at"?: string,"creator_id"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"id"?: string,"pitch"?: string | null,"rejection_reason"?: string | null,"sample_links"?: (string)[],"source"?: string,"status"?: string,"submitted_by"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaign_applications_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_applications_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"campaign_invites": {
                  Row: {
                    "application_id": string | null,"campaign_id": string,"creator_id": string,"id": string,"message": string | null,"responded_at": string | null,"sent_at": string,"sent_by": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "application_id"?: string | null,"campaign_id": string,"creator_id": string,"id"?: string,"message"?: string | null,"responded_at"?: string | null,"sent_at"?: string,"sent_by"?: string,"status"?: string
                  }
                  Update: {
                    "application_id"?: string | null,"campaign_id"?: string,"creator_id"?: string,"id"?: string,"message"?: string | null,"responded_at"?: string | null,"sent_at"?: string,"sent_by"?: string,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaign_invites_application_fk"
      columns: ["application_id"]
isOneToOne: false
      referencedRelation: "campaign_applications"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_invites_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_invites_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"campaign_programmes": {
                  Row: {
                    "campaign_id": string,"position": number,"programme_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "campaign_id": string,"position"?: number,"programme_id": number
                  }
                  Update: {
                    "campaign_id"?: string,"position"?: number,"programme_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaign_programmes_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns"
      referencedColumns: ["id"]
    }
                  ]
                },"campaigns": {
                  Row: {
                    "apply_by": string | null,"attribution_model": string | null,"brief_template_id": string | null,"budget_paise": number | null,"compensation_summary": string | null,"contract_template_id": string | null,"created_at": string,"created_by": string,"default_preset_id": string | null,"deliverables": NonNullable<Json>,"description": string | null,"eligibility": NonNullable<Json>,"ends_on": string | null,"id": string,"internal_notes": string | null,"link_message": string | null,"name": string,"objective": string,"opened_at": string | null,"owner_id": string | null,"slots": number | null,"starts_on": string | null,"status": string,"updated_at": string,"visibility": string
                  }
                  ComputedFields: never
                  Insert: {
                    "apply_by"?: string | null,"attribution_model"?: string | null,"brief_template_id"?: string | null,"budget_paise"?: number | null,"compensation_summary"?: string | null,"contract_template_id"?: string | null,"created_at"?: string,"created_by"?: string,"default_preset_id"?: string | null,"deliverables"?: NonNullable<Json>,"description"?: string | null,"eligibility"?: NonNullable<Json>,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"link_message"?: string | null,"name": string,"objective": string,"opened_at"?: string | null,"owner_id"?: string | null,"slots"?: number | null,"starts_on"?: string | null,"status"?: string,"updated_at"?: string,"visibility"?: string
                  }
                  Update: {
                    "apply_by"?: string | null,"attribution_model"?: string | null,"brief_template_id"?: string | null,"budget_paise"?: number | null,"compensation_summary"?: string | null,"contract_template_id"?: string | null,"created_at"?: string,"created_by"?: string,"default_preset_id"?: string | null,"deliverables"?: NonNullable<Json>,"description"?: string | null,"eligibility"?: NonNullable<Json>,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"link_message"?: string | null,"name"?: string,"objective"?: string,"opened_at"?: string | null,"owner_id"?: string | null,"slots"?: number | null,"starts_on"?: string | null,"status"?: string,"updated_at"?: string,"visibility"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaigns_brief_template_id_fkey"
      columns: ["brief_template_id"]
isOneToOne: false
      referencedRelation: "brief_templates"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_contract_template_id_fkey"
      columns: ["contract_template_id"]
isOneToOne: false
      referencedRelation: "contract_templates"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_default_preset_id_fkey"
      columns: ["default_preset_id"]
isOneToOne: false
      referencedRelation: "deal_presets"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_owner_id_fkey"
      columns: ["owner_id"]
isOneToOne: false
      referencedRelation: "staff_profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"clause_versions": {
                  Row: {
                    "body": NonNullable<Json>,"clause_id": string,"created_at": string,"created_by": string | null,"locked": boolean,"negotiable": boolean,"required": boolean,"reviewed_at": string | null,"reviewed_by": string | null,"title": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "body": NonNullable<Json>,"clause_id": string,"created_at"?: string,"created_by"?: string | null,"locked"?: boolean,"negotiable"?: boolean,"required"?: boolean,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"title": string,"version": number
                  }
                  Update: {
                    "body"?: NonNullable<Json>,"clause_id"?: string,"created_at"?: string,"created_by"?: string | null,"locked"?: boolean,"negotiable"?: boolean,"required"?: boolean,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"title"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "clause_versions_clause_id_fkey"
      columns: ["clause_id"]
isOneToOne: false
      referencedRelation: "clauses"
      referencedColumns: ["id"]
    }
                  ]
                },"clauses": {
                  Row: {
                    "archived_at": string | null,"category": string,"created_at": string,"created_by": string | null,"current_version": number,"deal_types": (string)[],"id": string,"key": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"category": string,"created_at"?: string,"created_by"?: string | null,"current_version"?: number,"deal_types"?: (string)[],"id"?: string,"key": string,"updated_at"?: string
                  }
                  Update: {
                    "archived_at"?: string | null,"category"?: string,"created_at"?: string,"created_by"?: string | null,"current_version"?: number,"deal_types"?: (string)[],"id"?: string,"key"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"client_grants": {
                  Row: {
                    "grantee": string,"object_name": string,"object_type": string,"privilege": string
                  }
                  ComputedFields: never
                  Insert: {
                    "grantee": string,"object_name": string,"object_type": string,"privilege": string
                  }
                  Update: {
                    "grantee"?: string,"object_name"?: string,"object_type"?: string,"privilege"?: string
                  }
                  Relationships: [
                    
                  ]
                },"communication_consents": {
                  Row: {
                    "channel": string,"created_at": string,"detail": string | null,"granted": boolean,"id": number,"purpose": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "channel": string,"created_at"?: string,"detail"?: string | null,"granted": boolean,"id"?: never,"purpose": string,"user_id": string
                  }
                  Update: {
                    "channel"?: string,"created_at"?: string,"detail"?: string | null,"granted"?: boolean,"id"?: never,"purpose"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"comp_runs": {
                  Row: {
                    "as_of": string,"created_at": string,"created_by": string | null,"deal_id": string,"deal_version_id": string | null,"id": number,"kind": string,"summary": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "as_of": string,"created_at"?: string,"created_by"?: string | null,"deal_id": string,"deal_version_id"?: string | null,"id"?: never,"kind": string,"summary"?: NonNullable<Json>
                  }
                  Update: {
                    "as_of"?: string,"created_at"?: string,"created_by"?: string | null,"deal_id"?: string,"deal_version_id"?: string | null,"id"?: never,"kind"?: string,"summary"?: NonNullable<Json>
                  }
                  Relationships: [
                    {
      foreignKeyName: "comp_runs_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "comp_runs_deal_version_id_fkey"
      columns: ["deal_version_id"]
isOneToOne: false
      referencedRelation: "deal_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"compliance_checks": {
                  Row: {
                    "created_at": string,"created_by": string | null,"deliverable_id": string,"id": string,"kind": string,"overridden": boolean,"overridden_at": string | null,"overridden_by": string | null,"override_reason": string | null,"passed": boolean,"result": NonNullable<Json>,"submission_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"deliverable_id": string,"id"?: string,"kind": string,"overridden"?: boolean,"overridden_at"?: string | null,"overridden_by"?: string | null,"override_reason"?: string | null,"passed": boolean,"result"?: NonNullable<Json>,"submission_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"deliverable_id"?: string,"id"?: string,"kind"?: string,"overridden"?: boolean,"overridden_at"?: string | null,"overridden_by"?: string | null,"override_reason"?: string | null,"passed"?: boolean,"result"?: NonNullable<Json>,"submission_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "compliance_checks_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "compliance_checks_submission_id_fkey"
      columns: ["submission_id"]
isOneToOne: false
      referencedRelation: "deliverable_submissions"
      referencedColumns: ["id"]
    }
                  ]
                },"consent_texts": {
                  Row: {
                    "body": string,"created_at": string,"created_by": string | null,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "body": string,"created_at"?: string,"created_by"?: string | null,"version": number
                  }
                  Update: {
                    "body"?: string,"created_at"?: string,"created_by"?: string | null,"version"?: number
                  }
                  Relationships: [
                    
                  ]
                },"contract_change_requests": {
                  Row: {
                    "clause_key": string | null,"contract_id": string,"created_at": string,"created_by": string,"decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"from_side": string,"id": string,"kind": string,"note": string | null,"proposed_body": Json | null,"proposed_terms": Json | null,"resolved_in_version_id": string | null,"status": string,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "clause_key"?: string | null,"contract_id": string,"created_at"?: string,"created_by"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"from_side": string,"id"?: string,"kind": string,"note"?: string | null,"proposed_body"?: Json | null,"proposed_terms"?: Json | null,"resolved_in_version_id"?: string | null,"status"?: string,"version_id": string
                  }
                  Update: {
                    "clause_key"?: string | null,"contract_id"?: string,"created_at"?: string,"created_by"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"from_side"?: string,"id"?: string,"kind"?: string,"note"?: string | null,"proposed_body"?: Json | null,"proposed_terms"?: Json | null,"resolved_in_version_id"?: string | null,"status"?: string,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contract_change_requests_contract_id_fkey"
      columns: ["contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_change_requests_resolved_in_version_id_fkey"
      columns: ["resolved_in_version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_change_requests_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"contract_comments": {
                  Row: {
                    "author_id": string,"author_side": string,"body": string,"clause_key": string,"contract_id": string,"created_at": string,"id": string,"parent_id": string | null,"resolved_at": string | null,"resolved_by": string | null,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id"?: string,"author_side": string,"body": string,"clause_key": string,"contract_id": string,"created_at"?: string,"id"?: string,"parent_id"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"version_id": string
                  }
                  Update: {
                    "author_id"?: string,"author_side"?: string,"body"?: string,"clause_key"?: string,"contract_id"?: string,"created_at"?: string,"id"?: string,"parent_id"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contract_comments_contract_id_fkey"
      columns: ["contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_comments_parent_id_fkey"
      columns: ["parent_id"]
isOneToOne: false
      referencedRelation: "contract_comments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_comments_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"contract_files": {
                  Row: {
                    "contract_id": string,"created_at": string,"id": string,"kind": string,"sha256": string,"storage_path": string,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "contract_id": string,"created_at"?: string,"id"?: string,"kind"?: string,"sha256": string,"storage_path": string,"version_id": string
                  }
                  Update: {
                    "contract_id"?: string,"created_at"?: string,"id"?: string,"kind"?: string,"sha256"?: string,"storage_path"?: string,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contract_files_contract_id_fkey"
      columns: ["contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_files_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"contract_sign_codes": {
                  Row: {
                    "attempts": number,"channel": string,"code_hash": string,"consumed_at": string | null,"contract_id": string,"created_at": string,"expires_at": string,"id": string,"role": string,"salt": string,"user_id": string,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempts"?: number,"channel": string,"code_hash": string,"consumed_at"?: string | null,"contract_id": string,"created_at"?: string,"expires_at": string,"id"?: string,"role": string,"salt": string,"user_id": string,"version_id": string
                  }
                  Update: {
                    "attempts"?: number,"channel"?: string,"code_hash"?: string,"consumed_at"?: string | null,"contract_id"?: string,"created_at"?: string,"expires_at"?: string,"id"?: string,"role"?: string,"salt"?: string,"user_id"?: string,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contract_sign_codes_contract_id_fkey"
      columns: ["contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_sign_codes_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"contract_templates": {
                  Row: {
                    "archived_at": string | null,"created_at": string,"created_by": string | null,"description": string | null,"footer": NonNullable<Json>,"header": NonNullable<Json>,"id": string,"is_default": boolean,"key": string | null,"name": string,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"footer"?: NonNullable<Json>,"header"?: NonNullable<Json>,"id"?: string,"is_default"?: boolean,"key"?: string | null,"name": string,"title": string,"updated_at"?: string
                  }
                  Update: {
                    "archived_at"?: string | null,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"footer"?: NonNullable<Json>,"header"?: NonNullable<Json>,"id"?: string,"is_default"?: boolean,"key"?: string | null,"name"?: string,"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"contract_versions": {
                  Row: {
                    "content": NonNullable<Json>,"contract_id": string,"created_at": string,"created_by": string | null,"deal_version_id": string,"html": string,"id": string,"missing_fields": (string)[],"note": string | null,"overrides": NonNullable<Json>,"sha256": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "content": NonNullable<Json>,"contract_id": string,"created_at"?: string,"created_by"?: string | null,"deal_version_id": string,"html": string,"id"?: string,"missing_fields"?: (string)[],"note"?: string | null,"overrides"?: NonNullable<Json>,"sha256": string,"version": number
                  }
                  Update: {
                    "content"?: NonNullable<Json>,"contract_id"?: string,"created_at"?: string,"created_by"?: string | null,"deal_version_id"?: string,"html"?: string,"id"?: string,"missing_fields"?: (string)[],"note"?: string | null,"overrides"?: NonNullable<Json>,"sha256"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "contract_versions_contract_id_fkey"
      columns: ["contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contract_versions_deal_version_id_fkey"
      columns: ["deal_version_id"]
isOneToOne: false
      referencedRelation: "deal_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"contracts": {
                  Row: {
                    "closed_at": string | null,"countersigned_at": string | null,"created_at": string,"created_by": string | null,"creator_signed_at": string | null,"current_version_id": string | null,"deal_id": string,"effective_on": string | null,"expires_on": string | null,"id": string,"integrity_failed_at": string | null,"kind": string,"negotiation_deadline": string | null,"number": string,"parent_contract_id": string | null,"payee_agency_id": string | null,"sent_at": string | null,"stamp_duty_reference": string | null,"status": string,"status_reason": string | null,"template_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "closed_at"?: string | null,"countersigned_at"?: string | null,"created_at"?: string,"created_by"?: string | null,"creator_signed_at"?: string | null,"current_version_id"?: string | null,"deal_id": string,"effective_on"?: string | null,"expires_on"?: string | null,"id"?: string,"integrity_failed_at"?: string | null,"kind"?: string,"negotiation_deadline"?: string | null,"number"?: string,"parent_contract_id"?: string | null,"payee_agency_id"?: string | null,"sent_at"?: string | null,"stamp_duty_reference"?: string | null,"status"?: string,"status_reason"?: string | null,"template_id": string,"updated_at"?: string
                  }
                  Update: {
                    "closed_at"?: string | null,"countersigned_at"?: string | null,"created_at"?: string,"created_by"?: string | null,"creator_signed_at"?: string | null,"current_version_id"?: string | null,"deal_id"?: string,"effective_on"?: string | null,"expires_on"?: string | null,"id"?: string,"integrity_failed_at"?: string | null,"kind"?: string,"negotiation_deadline"?: string | null,"number"?: string,"parent_contract_id"?: string | null,"payee_agency_id"?: string | null,"sent_at"?: string | null,"stamp_duty_reference"?: string | null,"status"?: string,"status_reason"?: string | null,"template_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contracts_current_version_fk"
      columns: ["current_version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contracts_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contracts_parent_contract_id_fkey"
      columns: ["parent_contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contracts_payee_agency_id_fkey"
      columns: ["payee_agency_id"]
isOneToOne: false
      referencedRelation: "agencies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contracts_template_id_fkey"
      columns: ["template_id"]
isOneToOne: false
      referencedRelation: "contract_templates"
      referencedColumns: ["id"]
    }
                  ]
                },"course_attempts": {
                  Row: {
                    "answers": NonNullable<Json>,"created_at": string,"creator_id": string,"id": string,"passed": boolean,"score_pct": number
                  }
                  ComputedFields: never
                  Insert: {
                    "answers": NonNullable<Json>,"created_at"?: string,"creator_id": string,"id"?: string,"passed": boolean,"score_pct": number
                  }
                  Update: {
                    "answers"?: NonNullable<Json>,"created_at"?: string,"creator_id"?: string,"id"?: string,"passed"?: boolean,"score_pct"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "course_attempts_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"course_lessons": {
                  Row: {
                    "active": boolean,"body": string,"id": string,"position": number,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"body": string,"id"?: string,"position": number,"title": string
                  }
                  Update: {
                    "active"?: boolean,"body"?: string,"id"?: string,"position"?: number,"title"?: string
                  }
                  Relationships: [
                    
                  ]
                },"course_questions": {
                  Row: {
                    "active": boolean,"correct_index": number,"explanation": string | null,"id": string,"options": (string)[],"position": number,"prompt": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"correct_index": number,"explanation"?: string | null,"id"?: string,"options": (string)[],"position": number,"prompt": string
                  }
                  Update: {
                    "active"?: boolean,"correct_index"?: number,"explanation"?: string | null,"id"?: string,"options"?: (string)[],"position"?: number,"prompt"?: string
                  }
                  Relationships: [
                    
                  ]
                },"creator_accounts": {
                  Row: {
                    "creator_id": string,"linked_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "creator_id": string,"linked_at"?: string,"user_id": string
                  }
                  Update: {
                    "creator_id"?: string,"linked_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_accounts_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: true
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_contacts": {
                  Row: {
                    "created_at": string,"created_by": string | null,"creator_id": string,"email_hash": string | null,"id": string,"kind": string,"label": string | null,"phone_hash": string | null,"phone_last2": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"creator_id": string,"email_hash"?: string | null,"id"?: string,"kind": string,"label"?: string | null,"phone_hash"?: string | null,"phone_last2"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"creator_id"?: string,"email_hash"?: string | null,"id"?: string,"kind"?: string,"label"?: string | null,"phone_hash"?: string | null,"phone_last2"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_contacts_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_imports": {
                  Row: {
                    "created": number,"created_at": string,"created_by": string,"duplicates": number,"errors": number,"file_name": string,"id": string,"report": NonNullable<Json>,"total": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created": number,"created_at"?: string,"created_by"?: string,"duplicates": number,"errors": number,"file_name": string,"id"?: string,"report": NonNullable<Json>,"total": number
                  }
                  Update: {
                    "created"?: number,"created_at"?: string,"created_by"?: string,"duplicates"?: number,"errors"?: number,"file_name"?: string,"id"?: string,"report"?: NonNullable<Json>,"total"?: number
                  }
                  Relationships: [
                    
                  ]
                },"creator_invitations": {
                  Row: {
                    "accepted_at": string | null,"creator_id": string,"email": string,"expires_at": string,"id": string,"sent_at": string,"sent_by": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accepted_at"?: string | null,"creator_id": string,"email": string,"expires_at"?: string,"id"?: string,"sent_at"?: string,"sent_by"?: string,"status"?: string
                  }
                  Update: {
                    "accepted_at"?: string | null,"creator_id"?: string,"email"?: string,"expires_at"?: string,"id"?: string,"sent_at"?: string,"sent_by"?: string,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_invitations_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_kyc": {
                  Row: {
                    "account_holder": string | null,"bank_account_enc": string | null,"bank_last4": string | null,"creator_id": string,"gst_status": string,"gstin": string | null,"gstin_verified": boolean,"ifsc": string | null,"name_on_pan": string | null,"pan_enc": string | null,"pan_last4": string | null,"proof_path": string | null,"rejection_reason": string | null,"status": string,"submitted_at": string | null,"updated_at": string,"verified_at": string | null,"verified_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "account_holder"?: string | null,"bank_account_enc"?: string | null,"bank_last4"?: string | null,"creator_id": string,"gst_status"?: string,"gstin"?: string | null,"gstin_verified"?: boolean,"ifsc"?: string | null,"name_on_pan"?: string | null,"pan_enc"?: string | null,"pan_last4"?: string | null,"proof_path"?: string | null,"rejection_reason"?: string | null,"status"?: string,"submitted_at"?: string | null,"updated_at"?: string,"verified_at"?: string | null,"verified_by"?: string | null
                  }
                  Update: {
                    "account_holder"?: string | null,"bank_account_enc"?: string | null,"bank_last4"?: string | null,"creator_id"?: string,"gst_status"?: string,"gstin"?: string | null,"gstin_verified"?: boolean,"ifsc"?: string | null,"name_on_pan"?: string | null,"pan_enc"?: string | null,"pan_last4"?: string | null,"proof_path"?: string | null,"rejection_reason"?: string | null,"status"?: string,"submitted_at"?: string | null,"updated_at"?: string,"verified_at"?: string | null,"verified_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_kyc_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: true
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_lead_feed": {
                  Row: {
                    "attribution_id": string,"attribution_reason": string | null,"attribution_status": string,"campaign_id": string | null,"campaign_name": string | null,"code": string,"creator_id": string,"creator_stage": string,"deal_id": string | null,"deal_title": string | null,"deliverable_id": string | null,"deliverable_title": string | null,"display_name": string | null,"earning_status": string,"email_masked": string | null,"fields": NonNullable<Json>,"flags": (string)[],"is_test": boolean,"lead_at": string,"lead_ref": string,"link_id": string | null,"link_label": string | null,"phone_masked": string,"programme_id": number | null,"programme_name": string | null,"reason_category": string | null,"removed": boolean,"stage_changed_at": string | null,"stage_timeline": NonNullable<Json>,"temperature": string | null,"touch": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attribution_id": string,"attribution_reason"?: string | null,"attribution_status": string,"campaign_id"?: string | null,"campaign_name"?: string | null,"code": string,"creator_id": string,"creator_stage": string,"deal_id"?: string | null,"deal_title"?: string | null,"deliverable_id"?: string | null,"deliverable_title"?: string | null,"display_name"?: string | null,"earning_status"?: string,"email_masked"?: string | null,"fields"?: NonNullable<Json>,"flags"?: (string)[],"is_test"?: boolean,"lead_at": string,"lead_ref": string,"link_id"?: string | null,"link_label"?: string | null,"phone_masked": string,"programme_id"?: number | null,"programme_name"?: string | null,"reason_category"?: string | null,"removed"?: boolean,"stage_changed_at"?: string | null,"stage_timeline"?: NonNullable<Json>,"temperature"?: string | null,"touch": string,"updated_at"?: string
                  }
                  Update: {
                    "attribution_id"?: string,"attribution_reason"?: string | null,"attribution_status"?: string,"campaign_id"?: string | null,"campaign_name"?: string | null,"code"?: string,"creator_id"?: string,"creator_stage"?: string,"deal_id"?: string | null,"deal_title"?: string | null,"deliverable_id"?: string | null,"deliverable_title"?: string | null,"display_name"?: string | null,"earning_status"?: string,"email_masked"?: string | null,"fields"?: NonNullable<Json>,"flags"?: (string)[],"is_test"?: boolean,"lead_at"?: string,"lead_ref"?: string,"link_id"?: string | null,"link_label"?: string | null,"phone_masked"?: string,"programme_id"?: number | null,"programme_name"?: string | null,"reason_category"?: string | null,"removed"?: boolean,"stage_changed_at"?: string | null,"stage_timeline"?: NonNullable<Json>,"temperature"?: string | null,"touch"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_lead_feed_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: true
      referencedRelation: "an_leads"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "creator_lead_feed_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: true
      referencedRelation: "an_leads_live"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "creator_lead_feed_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: true
      referencedRelation: "an_revenue"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "creator_lead_feed_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: true
      referencedRelation: "lead_attributions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "creator_lead_feed_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_platforms": {
                  Row: {
                    "audience": NonNullable<Json>,"avg_views": number | null,"created_at": string,"creator_id": string,"engagement_rate": number | null,"followers": number | null,"handle": string,"id": string,"platform": string,"source": string,"stats_updated_at": string | null,"updated_at": string,"url": string
                  }
                  ComputedFields: never
                  Insert: {
                    "audience"?: NonNullable<Json>,"avg_views"?: number | null,"created_at"?: string,"creator_id": string,"engagement_rate"?: number | null,"followers"?: number | null,"handle": string,"id"?: string,"platform": string,"source"?: string,"stats_updated_at"?: string | null,"updated_at"?: string,"url": string
                  }
                  Update: {
                    "audience"?: NonNullable<Json>,"avg_views"?: number | null,"created_at"?: string,"creator_id"?: string,"engagement_rate"?: number | null,"followers"?: number | null,"handle"?: string,"id"?: string,"platform"?: string,"source"?: string,"stats_updated_at"?: string | null,"updated_at"?: string,"url"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_platforms_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_portfolio": {
                  Row: {
                    "caption": string | null,"created_at": string,"creator_id": string,"id": string,"position": number,"title": string | null,"url": string
                  }
                  ComputedFields: never
                  Insert: {
                    "caption"?: string | null,"created_at"?: string,"creator_id": string,"id"?: string,"position"?: number,"title"?: string | null,"url": string
                  }
                  Update: {
                    "caption"?: string | null,"created_at"?: string,"creator_id"?: string,"id"?: string,"position"?: number,"title"?: string | null,"url"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_portfolio_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_rate_cards": {
                  Row: {
                    "created_at": string,"creator_id": string,"format": string,"id": string,"notes": string | null,"platform": string,"suggested_paise": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"creator_id": string,"format": string,"id"?: string,"notes"?: string | null,"platform": string,"suggested_paise": number,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"creator_id"?: string,"format"?: string,"id"?: string,"notes"?: string | null,"platform"?: string,"suggested_paise"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_rate_cards_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_tier_state": {
                  Row: {
                    "creator_id": string,"manual_reason": string | null,"manual_tier_id": string | null,"manual_until": string | null,"months_below": number,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "creator_id": string,"manual_reason"?: string | null,"manual_tier_id"?: string | null,"manual_until"?: string | null,"months_below"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "creator_id"?: string,"manual_reason"?: string | null,"manual_tier_id"?: string | null,"manual_until"?: string | null,"months_below"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_tier_state_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: true
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "creator_tier_state_manual_tier_id_fkey"
      columns: ["manual_tier_id"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    }
                  ]
                },"creators": {
                  Row: {
                    "approved_at": string | null,"approved_by": string | null,"avatar_path": string | null,"bio": string | null,"blocked_reason": string | null,"city": string | null,"created_at": string,"created_by": string | null,"display_name": string,"email": string | null,"handle": string,"id": string,"is_blocked": boolean,"is_test": boolean,"languages": (string)[],"last_activity_at": string | null,"last_contacted_at": string | null,"leaderboard_opt_in": boolean,"legal_name": string | null,"media_kit_show_rates": boolean,"niches": (string)[],"onboarding_step": string,"onboarding_submitted_at": string | null,"owner_id": string | null,"phone_e164": string | null,"pipeline_stage": string,"public_page_enabled": boolean,"source": string | null,"state": string | null,"status": string,"tags": (string)[],"tier_id": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "approved_at"?: string | null,"approved_by"?: string | null,"avatar_path"?: string | null,"bio"?: string | null,"blocked_reason"?: string | null,"city"?: string | null,"created_at"?: string,"created_by"?: string | null,"display_name": string,"email"?: string | null,"handle": string,"id"?: string,"is_blocked"?: boolean,"is_test"?: boolean,"languages"?: (string)[],"last_activity_at"?: string | null,"last_contacted_at"?: string | null,"leaderboard_opt_in"?: boolean,"legal_name"?: string | null,"media_kit_show_rates"?: boolean,"niches"?: (string)[],"onboarding_step"?: string,"onboarding_submitted_at"?: string | null,"owner_id"?: string | null,"phone_e164"?: string | null,"pipeline_stage"?: string,"public_page_enabled"?: boolean,"source"?: string | null,"state"?: string | null,"status"?: string,"tags"?: (string)[],"tier_id"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "approved_at"?: string | null,"approved_by"?: string | null,"avatar_path"?: string | null,"bio"?: string | null,"blocked_reason"?: string | null,"city"?: string | null,"created_at"?: string,"created_by"?: string | null,"display_name"?: string,"email"?: string | null,"handle"?: string,"id"?: string,"is_blocked"?: boolean,"is_test"?: boolean,"languages"?: (string)[],"last_activity_at"?: string | null,"last_contacted_at"?: string | null,"leaderboard_opt_in"?: boolean,"legal_name"?: string | null,"media_kit_show_rates"?: boolean,"niches"?: (string)[],"onboarding_step"?: string,"onboarding_submitted_at"?: string | null,"owner_id"?: string | null,"phone_e164"?: string | null,"pipeline_stage"?: string,"public_page_enabled"?: boolean,"source"?: string | null,"state"?: string | null,"status"?: string,"tags"?: (string)[],"tier_id"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "creators_owner_id_fkey"
      columns: ["owner_id"]
isOneToOne: false
      referencedRelation: "staff_profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "creators_tier_id_fkey"
      columns: ["tier_id"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    }
                  ]
                },"deal_manual_events": {
                  Row: {
                    "at": string,"created_by": string,"deal_id": string,"id": string,"kind": string,"reason": string,"ref": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "at"?: string,"created_by"?: string,"deal_id": string,"id"?: string,"kind": string,"reason": string,"ref"?: string | null
                  }
                  Update: {
                    "at"?: string,"created_by"?: string,"deal_id"?: string,"id"?: string,"kind"?: string,"reason"?: string,"ref"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "deal_manual_events_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    }
                  ]
                },"deal_presets": {
                  Row: {
                    "archived_at": string | null,"comp_config": NonNullable<Json>,"created_at": string,"created_by": string | null,"description": string | null,"id": string,"is_system": boolean,"key": string | null,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"comp_config": NonNullable<Json>,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"id"?: string,"is_system"?: boolean,"key"?: string | null,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "archived_at"?: string | null,"comp_config"?: NonNullable<Json>,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"id"?: string,"is_system"?: boolean,"key"?: string | null,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"deal_versions": {
                  Row: {
                    "comp_config": NonNullable<Json>,"config_hash": string,"deal_id": string,"decided_at": string | null,"decided_by": string | null,"decision_reason": string | null,"effective_from": string,"id": string,"is_signed": boolean,"note": string | null,"origin": string,"preset_id": string | null,"proposed_at": string,"proposed_by": string | null,"state": string,"version": number,"deal_version_json": Json | null
                  }
                  ComputedFields: "deal_version_json"
                  Insert: {
                    "comp_config": NonNullable<Json>,"config_hash": string,"deal_id": string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"effective_from": string,"id"?: string,"is_signed"?: boolean,"note"?: string | null,"origin": string,"preset_id"?: string | null,"proposed_at"?: string,"proposed_by"?: string | null,"state"?: string,"version": number
                  }
                  Update: {
                    "comp_config"?: NonNullable<Json>,"config_hash"?: string,"deal_id"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"effective_from"?: string,"id"?: string,"is_signed"?: boolean,"note"?: string | null,"origin"?: string,"preset_id"?: string | null,"proposed_at"?: string,"proposed_by"?: string | null,"state"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "deal_versions_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deal_versions_preset_id_fkey"
      columns: ["preset_id"]
isOneToOne: false
      referencedRelation: "deal_presets"
      referencedColumns: ["id"]
    }
                  ]
                },"deals": {
                  Row: {
                    "activated_at": string | null,"agreed_at": string | null,"agreed_terms": Json | null,"application_id": string | null,"campaign_id": string | null,"closed_at": string | null,"code": string,"committed_at": string | null,"committed_paise": number | null,"created_at": string,"created_by": string | null,"creator_id": string,"current_version_id": string | null,"deal_model": string,"draft_config": Json | null,"ends_on": string | null,"id": string,"internal_notes": string | null,"owner_id": string | null,"preset_id": string | null,"renewal_of": string | null,"starts_on": string,"status": string,"status_reason": string | null,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "activated_at"?: string | null,"agreed_at"?: string | null,"agreed_terms"?: Json | null,"application_id"?: string | null,"campaign_id"?: string | null,"closed_at"?: string | null,"code"?: string,"committed_at"?: string | null,"committed_paise"?: number | null,"created_at"?: string,"created_by"?: string | null,"creator_id": string,"current_version_id"?: string | null,"deal_model"?: string,"draft_config"?: Json | null,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"owner_id"?: string | null,"preset_id"?: string | null,"renewal_of"?: string | null,"starts_on": string,"status"?: string,"status_reason"?: string | null,"title": string,"updated_at"?: string
                  }
                  Update: {
                    "activated_at"?: string | null,"agreed_at"?: string | null,"agreed_terms"?: Json | null,"application_id"?: string | null,"campaign_id"?: string | null,"closed_at"?: string | null,"code"?: string,"committed_at"?: string | null,"committed_paise"?: number | null,"created_at"?: string,"created_by"?: string | null,"creator_id"?: string,"current_version_id"?: string | null,"deal_model"?: string,"draft_config"?: Json | null,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"owner_id"?: string | null,"preset_id"?: string | null,"renewal_of"?: string | null,"starts_on"?: string,"status"?: string,"status_reason"?: string | null,"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "deals_application_id_fkey"
      columns: ["application_id"]
isOneToOne: true
      referencedRelation: "campaign_applications"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_current_version_fk"
      columns: ["current_version_id"]
isOneToOne: false
      referencedRelation: "deal_versions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_owner_id_fkey"
      columns: ["owner_id"]
isOneToOne: false
      referencedRelation: "staff_profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "deals_preset_id_fkey"
      columns: ["preset_id"]
isOneToOne: false
      referencedRelation: "deal_presets"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_renewal_of_fkey"
      columns: ["renewal_of"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    }
                  ]
                },"deliverable_submissions": {
                  Row: {
                    "author_side": string,"body": string | null,"created_at": string,"created_by": string | null,"creator_note": string | null,"decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"deliverable_id": string,"files": NonNullable<Json>,"id": string,"kind": string,"link_url": string | null,"status": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "author_side": string,"body"?: string | null,"created_at"?: string,"created_by"?: string | null,"creator_note"?: string | null,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id": string,"files"?: NonNullable<Json>,"id"?: string,"kind": string,"link_url"?: string | null,"status"?: string,"version": number
                  }
                  Update: {
                    "author_side"?: string,"body"?: string | null,"created_at"?: string,"created_by"?: string | null,"creator_note"?: string | null,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id"?: string,"files"?: NonNullable<Json>,"id"?: string,"kind"?: string,"link_url"?: string | null,"status"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "deliverable_submissions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    }
                  ]
                },"deliverable_transitions": {
                  Row: {
                    "action": string,"actor_id": string | null,"actor_side": string,"at": string,"deliverable_id": string,"from_status": string,"id": number,"note": string | null,"to_status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_id"?: string | null,"actor_side": string,"at"?: string,"deliverable_id": string,"from_status": string,"id"?: never,"note"?: string | null,"to_status": string
                  }
                  Update: {
                    "action"?: string,"actor_id"?: string | null,"actor_side"?: string,"at"?: string,"deliverable_id"?: string,"from_status"?: string,"id"?: never,"note"?: string | null,"to_status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "deliverable_transitions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    }
                  ]
                },"deliverables": {
                  Row: {
                    "brief_id": string | null,"cancelled_at": string | null,"code": string,"completed_at": string | null,"concept_approved_at": string | null,"config_ref": string | null,"created_at": string,"created_by": string | null,"deal_id": string,"disclosure_failed_at": string | null,"draft_approved_at": string | null,"due_dates": NonNullable<Json>,"extra_revisions": number,"format": string,"id": string,"live_at": string | null,"platform": string,"position": number,"revision_limit": number,"revisions_used": number,"scheduled_for": string | null,"specs": NonNullable<Json>,"stages": NonNullable<Json>,"status": string,"status_reason": string | null,"title": string,"updated_at": string,"verified_at": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "brief_id"?: string | null,"cancelled_at"?: string | null,"code"?: string,"completed_at"?: string | null,"concept_approved_at"?: string | null,"config_ref"?: string | null,"created_at"?: string,"created_by"?: string | null,"deal_id": string,"disclosure_failed_at"?: string | null,"draft_approved_at"?: string | null,"due_dates"?: NonNullable<Json>,"extra_revisions"?: number,"format": string,"id"?: string,"live_at"?: string | null,"platform": string,"position"?: number,"revision_limit"?: number,"revisions_used"?: number,"scheduled_for"?: string | null,"specs"?: NonNullable<Json>,"stages"?: NonNullable<Json>,"status"?: string,"status_reason"?: string | null,"title": string,"updated_at"?: string,"verified_at"?: string | null
                  }
                  Update: {
                    "brief_id"?: string | null,"cancelled_at"?: string | null,"code"?: string,"completed_at"?: string | null,"concept_approved_at"?: string | null,"config_ref"?: string | null,"created_at"?: string,"created_by"?: string | null,"deal_id"?: string,"disclosure_failed_at"?: string | null,"draft_approved_at"?: string | null,"due_dates"?: NonNullable<Json>,"extra_revisions"?: number,"format"?: string,"id"?: string,"live_at"?: string | null,"platform"?: string,"position"?: number,"revision_limit"?: number,"revisions_used"?: number,"scheduled_for"?: string | null,"specs"?: NonNullable<Json>,"stages"?: NonNullable<Json>,"status"?: string,"status_reason"?: string | null,"title"?: string,"updated_at"?: string,"verified_at"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "deliverables_brief_id_fkey"
      columns: ["brief_id"]
isOneToOne: false
      referencedRelation: "briefs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deliverables_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    }
                  ]
                },"digest_preferences": {
                  Row: {
                    "channel": string,"frequency": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "channel"?: string,"frequency": string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "channel"?: string,"frequency"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"domain_events": {
                  Row: {
                    "actor_id": string | null,"id": number,"idem_key": string,"occurred_at": string,"payload": NonNullable<Json>,"subject_id": string,"subject_type": string,"type": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actor_id"?: string | null,"id"?: never,"idem_key": string,"occurred_at"?: string,"payload"?: NonNullable<Json>,"subject_id": string,"subject_type": string,"type": string
                  }
                  Update: {
                    "actor_id"?: string | null,"id"?: never,"idem_key"?: string,"occurred_at"?: string,"payload"?: NonNullable<Json>,"subject_id"?: string,"subject_type"?: string,"type"?: string
                  }
                  Relationships: [
                    
                  ]
                },"eduwit_commission_receipts": {
                  Row: {
                    "created_at": string,"enrollment_ref": string,"enrollment_status": string | null,"entered_by": string | null,"gross_paise": number,"gst_paise": number,"id": number,"net_paise": number,"reason": string | null,"received_on": string | null,"received_paise": number,"source": string,"source_version": string,"status": string,"student_lead_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"enrollment_ref": string,"enrollment_status"?: string | null,"entered_by"?: string | null,"gross_paise"?: number,"gst_paise"?: number,"id"?: never,"net_paise"?: number,"reason"?: string | null,"received_on"?: string | null,"received_paise"?: number,"source": string,"source_version": string,"status": string,"student_lead_id": number
                  }
                  Update: {
                    "created_at"?: string,"enrollment_ref"?: string,"enrollment_status"?: string | null,"entered_by"?: string | null,"gross_paise"?: number,"gst_paise"?: number,"id"?: never,"net_paise"?: number,"reason"?: string | null,"received_on"?: string | null,"received_paise"?: number,"source"?: string,"source_version"?: string,"status"?: string,"student_lead_id"?: number
                  }
                  Relationships: [
                    
                  ]
                },"email_codes": {
                  Row: {
                    "attempts": number,"code_hash": string,"consumed_at": string | null,"created_at": string,"expires_at": string,"id": string,"purpose": string,"salt": string,"session_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempts"?: number,"code_hash": string,"consumed_at"?: string | null,"created_at"?: string,"expires_at": string,"id"?: string,"purpose"?: string,"salt": string,"session_id": string,"user_id": string
                  }
                  Update: {
                    "attempts"?: number,"code_hash"?: string,"consumed_at"?: string | null,"created_at"?: string,"expires_at"?: string,"id"?: string,"purpose"?: string,"salt"?: string,"session_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"fraud_flags": {
                  Row: {
                    "attribution_id": string | null,"creator_id": string,"decided_at": string | null,"decided_by": string | null,"detail": NonNullable<Json>,"id": string,"note": string | null,"opened_at": string,"signal": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attribution_id"?: string | null,"creator_id": string,"decided_at"?: string | null,"decided_by"?: string | null,"detail"?: NonNullable<Json>,"id"?: string,"note"?: string | null,"opened_at"?: string,"signal": string,"status"?: string
                  }
                  Update: {
                    "attribution_id"?: string | null,"creator_id"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"detail"?: NonNullable<Json>,"id"?: string,"note"?: string | null,"opened_at"?: string,"signal"?: string,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "fraud_flags_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "fraud_flags_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads_live"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "fraud_flags_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_revenue"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "fraud_flags_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "lead_attributions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "fraud_flags_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"invoices": {
                  Row: {
                    "created_at": string,"creator_id": string,"file_path": string | null,"gst_paise": number,"gstin": string | null,"id": string,"issued_on": string,"kind": string,"number": string,"payout_id": string,"review_note": string | null,"reviewed_at": string | null,"reviewed_by": string | null,"status": string,"taxable_paise": number,"total_paise": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"creator_id": string,"file_path"?: string | null,"gst_paise"?: number,"gstin"?: string | null,"id"?: string,"issued_on": string,"kind": string,"number": string,"payout_id": string,"review_note"?: string | null,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"status"?: string,"taxable_paise": number,"total_paise": number
                  }
                  Update: {
                    "created_at"?: string,"creator_id"?: string,"file_path"?: string | null,"gst_paise"?: number,"gstin"?: string | null,"id"?: string,"issued_on"?: string,"kind"?: string,"number"?: string,"payout_id"?: string,"review_note"?: string | null,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"status"?: string,"taxable_paise"?: number,"total_paise"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "invoices_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invoices_payout_id_fkey"
      columns: ["payout_id"]
isOneToOne: false
      referencedRelation: "payouts"
      referencedColumns: ["id"]
    }
                  ]
                },"jobs": {
                  Row: {
                    "attempts": number,"created_at": string,"finished_at": string | null,"id": number,"idem_key": string | null,"kind": string,"last_error": string | null,"locked_at": string | null,"locked_by": string | null,"max_attempts": number,"payload": NonNullable<Json>,"run_at": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempts"?: number,"created_at"?: string,"finished_at"?: string | null,"id"?: never,"idem_key"?: string | null,"kind": string,"last_error"?: string | null,"locked_at"?: string | null,"locked_by"?: string | null,"max_attempts"?: number,"payload"?: NonNullable<Json>,"run_at"?: string,"status"?: string
                  }
                  Update: {
                    "attempts"?: number,"created_at"?: string,"finished_at"?: string | null,"id"?: never,"idem_key"?: string | null,"kind"?: string,"last_error"?: string | null,"locked_at"?: string | null,"locked_by"?: string | null,"max_attempts"?: number,"payload"?: NonNullable<Json>,"run_at"?: string,"status"?: string
                  }
                  Relationships: [
                    
                  ]
                },"lead_attributions": {
                  Row: {
                    "campaign_id": string | null,"code": string,"created_at": string,"creator_id": string,"creator_stage": string | null,"deal_id": string | null,"decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"deliverable_id": string | null,"evidence_source": string,"id": string,"is_test": boolean,"lead_created_at": string,"link_id": string | null,"reason": string | null,"stage_flags": (string)[],"stage_reason": string | null,"status": string,"student_lead_id": number,"touch": string,"touch_at": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "campaign_id"?: string | null,"code": string,"created_at"?: string,"creator_id": string,"creator_stage"?: string | null,"deal_id"?: string | null,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id"?: string | null,"evidence_source": string,"id"?: string,"is_test"?: boolean,"lead_created_at": string,"link_id"?: string | null,"reason"?: string | null,"stage_flags"?: (string)[],"stage_reason"?: string | null,"status": string,"student_lead_id": number,"touch": string,"touch_at": string,"updated_at"?: string
                  }
                  Update: {
                    "campaign_id"?: string | null,"code"?: string,"created_at"?: string,"creator_id"?: string,"creator_stage"?: string | null,"deal_id"?: string | null,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id"?: string | null,"evidence_source"?: string,"id"?: string,"is_test"?: boolean,"lead_created_at"?: string,"link_id"?: string | null,"reason"?: string | null,"stage_flags"?: (string)[],"stage_reason"?: string | null,"status"?: string,"student_lead_id"?: number,"touch"?: string,"touch_at"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "lead_attributions_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    }
                  ]
                },"lead_stage_events": {
                  Row: {
                    "attribution_id": string,"created_at": string,"creator_stage": string,"flags": (string)[],"id": number,"idem_key": string,"occurred_at": string,"reason_category": string | null,"source": string,"student_lead_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "attribution_id": string,"created_at"?: string,"creator_stage": string,"flags"?: (string)[],"id"?: never,"idem_key": string,"occurred_at": string,"reason_category"?: string | null,"source": string,"student_lead_id": number
                  }
                  Update: {
                    "attribution_id"?: string,"created_at"?: string,"creator_stage"?: string,"flags"?: (string)[],"id"?: never,"idem_key"?: string,"occurred_at"?: string,"reason_category"?: string | null,"source"?: string,"student_lead_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "lead_stage_events_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "lead_stage_events_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads_live"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "lead_stage_events_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_revenue"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "lead_stage_events_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "lead_attributions"
      referencedColumns: ["id"]
    }
                  ]
                },"ledger_entries": {
                  Row: {
                    "amount_paise": number,"attribution_id": string | null,"confirmed_paise": number,"creator_id": string,"deal_id": string | null,"deal_version_id": string | null,"direction": string,"due_on": string,"event_key": string,"held": boolean,"hold_reason": string | null,"id": number,"note": string | null,"paid_paise": number,"payout_id": string | null,"period": string,"posted_at": string,"posted_by": string | null,"reversed_by_id": number | null,"reverses_id": number | null,"rule_id": string | null,"source": string,"status": string,"subject": string | null,"tds_component": string | null,"type": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paise": number,"attribution_id"?: string | null,"confirmed_paise"?: number,"creator_id": string,"deal_id"?: string | null,"deal_version_id"?: string | null,"direction": string,"due_on": string,"event_key": string,"held"?: boolean,"hold_reason"?: string | null,"id"?: never,"note"?: string | null,"paid_paise"?: number,"payout_id"?: string | null,"period": string,"posted_at"?: string,"posted_by"?: string | null,"reversed_by_id"?: number | null,"reverses_id"?: number | null,"rule_id"?: string | null,"source": string,"status": string,"subject"?: string | null,"tds_component"?: string | null,"type": string,"updated_at"?: string
                  }
                  Update: {
                    "amount_paise"?: number,"attribution_id"?: string | null,"confirmed_paise"?: number,"creator_id"?: string,"deal_id"?: string | null,"deal_version_id"?: string | null,"direction"?: string,"due_on"?: string,"event_key"?: string,"held"?: boolean,"hold_reason"?: string | null,"id"?: never,"note"?: string | null,"paid_paise"?: number,"payout_id"?: string | null,"period"?: string,"posted_at"?: string,"posted_by"?: string | null,"reversed_by_id"?: number | null,"reverses_id"?: number | null,"rule_id"?: string | null,"source"?: string,"status"?: string,"subject"?: string | null,"tds_component"?: string | null,"type"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ledger_entries_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "ledger_entries_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_leads_live"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "ledger_entries_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "an_revenue"
      referencedColumns: ["attribution_id"]
    },{
      foreignKeyName: "ledger_entries_attribution_id_fkey"
      columns: ["attribution_id"]
isOneToOne: false
      referencedRelation: "lead_attributions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_deal_version_id_fkey"
      columns: ["deal_version_id"]
isOneToOne: false
      referencedRelation: "deal_versions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_payout_fk"
      columns: ["payout_id"]
isOneToOne: false
      referencedRelation: "payouts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_reversed_by_id_fkey"
      columns: ["reversed_by_id"]
isOneToOne: false
      referencedRelation: "ledger_entries"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_reverses_id_fkey"
      columns: ["reverses_id"]
isOneToOne: true
      referencedRelation: "ledger_entries"
      referencedColumns: ["id"]
    }
                  ]
                },"ledger_status_events": {
                  Row: {
                    "actor_id": string | null,"at": string,"entry_id": number,"from_status": string | null,"id": number,"reason": string | null,"to_status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actor_id"?: string | null,"at"?: string,"entry_id": number,"from_status"?: string | null,"id"?: never,"reason"?: string | null,"to_status": string
                  }
                  Update: {
                    "actor_id"?: string | null,"at"?: string,"entry_id"?: number,"from_status"?: string | null,"id"?: never,"reason"?: string | null,"to_status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ledger_status_events_entry_id_fkey"
      columns: ["entry_id"]
isOneToOne: false
      referencedRelation: "ledger_entries"
      referencedColumns: ["id"]
    }
                  ]
                },"link_clicks": {
                  Row: {
                    "clicked_at": string,"device": string | null,"id": number,"in_app": string | null,"ip_hash": string | null,"is_bot": boolean,"issue_failed": boolean,"link_id": string,"referrer": string | null,"user_agent": string | null,"w2_access_code": string | null,"w2_click_id": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "clicked_at"?: string,"device"?: string | null,"id"?: never,"in_app"?: string | null,"ip_hash"?: string | null,"is_bot"?: boolean,"issue_failed"?: boolean,"link_id": string,"referrer"?: string | null,"user_agent"?: string | null,"w2_access_code"?: string | null,"w2_click_id"?: number | null
                  }
                  Update: {
                    "clicked_at"?: string,"device"?: string | null,"id"?: never,"in_app"?: string | null,"ip_hash"?: string | null,"is_bot"?: boolean,"issue_failed"?: boolean,"link_id"?: string,"referrer"?: string | null,"user_agent"?: string | null,"w2_access_code"?: string | null,"w2_click_id"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "link_clicks_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    }
                  ]
                },"message_attachments": {
                  Row: {
                    "id": string,"message_id": string,"mime": string,"name": string,"path": string,"size_bytes": number
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"message_id": string,"mime": string,"name": string,"path": string,"size_bytes": number
                  }
                  Update: {
                    "id"?: string,"message_id"?: string,"mime"?: string,"name"?: string,"path"?: string,"size_bytes"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "message_attachments_message_id_fkey"
      columns: ["message_id"]
isOneToOne: false
      referencedRelation: "messages"
      referencedColumns: ["id"]
    }
                  ]
                },"message_mentions": {
                  Row: {
                    "message_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "message_id": string,"user_id": string
                  }
                  Update: {
                    "message_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "message_mentions_message_id_fkey"
      columns: ["message_id"]
isOneToOne: false
      referencedRelation: "messages"
      referencedColumns: ["id"]
    }
                  ]
                },"messages": {
                  Row: {
                    "author_id": string,"author_side": string,"body": string,"created_at": string,"id": string,"search": unknown,"thread_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id"?: string,"author_side": string,"body": string,"created_at"?: string,"id"?: string,"search"?: never,"thread_id": string
                  }
                  Update: {
                    "author_id"?: string,"author_side"?: string,"body"?: string,"created_at"?: string,"id"?: string,"search"?: never,"thread_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "messages_thread_id_fkey"
      columns: ["thread_id"]
isOneToOne: false
      referencedRelation: "threads"
      referencedColumns: ["id"]
    }
                  ]
                },"notification_deliveries": {
                  Row: {
                    "attempts": number,"channel": string,"created_at": string,"error": string | null,"id": number,"notification_id": string,"provider": string | null,"provider_ref": string | null,"sent_at": string | null,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempts"?: number,"channel": string,"created_at"?: string,"error"?: string | null,"id"?: never,"notification_id": string,"provider"?: string | null,"provider_ref"?: string | null,"sent_at"?: string | null,"status"?: string
                  }
                  Update: {
                    "attempts"?: number,"channel"?: string,"created_at"?: string,"error"?: string | null,"id"?: never,"notification_id"?: string,"provider"?: string | null,"provider_ref"?: string | null,"sent_at"?: string | null,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "notification_deliveries_notification_id_fkey"
      columns: ["notification_id"]
isOneToOne: false
      referencedRelation: "notifications"
      referencedColumns: ["id"]
    }
                  ]
                },"notification_events": {
                  Row: {
                    "audience": (string)[],"channels": (string)[],"event": string,"grp": string,"mandatory": boolean,"vars": (string)[]
                  }
                  ComputedFields: never
                  Insert: {
                    "audience": (string)[],"channels": (string)[],"event": string,"grp": string,"mandatory": boolean,"vars": (string)[]
                  }
                  Update: {
                    "audience"?: (string)[],"channels"?: (string)[],"event"?: string,"grp"?: string,"mandatory"?: boolean,"vars"?: (string)[]
                  }
                  Relationships: [
                    
                  ]
                },"notification_preferences": {
                  Row: {
                    "channel": string,"enabled": boolean,"event": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "channel": string,"enabled": boolean,"event": string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "channel"?: string,"enabled"?: boolean,"event"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"notification_templates": {
                  Row: {
                    "active": boolean,"body": string,"channel": string,"created_at": string,"event": string,"id": string,"locale": string,"subject": string | null,"updated_at": string,"updated_by": string | null,"version": number,"wa_template_name": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"body": string,"channel": string,"created_at"?: string,"event": string,"id"?: string,"locale"?: string,"subject"?: string | null,"updated_at"?: string,"updated_by"?: string | null,"version"?: number,"wa_template_name"?: string | null
                  }
                  Update: {
                    "active"?: boolean,"body"?: string,"channel"?: string,"created_at"?: string,"event"?: string,"id"?: string,"locale"?: string,"subject"?: string | null,"updated_at"?: string,"updated_by"?: string | null,"version"?: number,"wa_template_name"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"notifications": {
                  Row: {
                    "body": string | null,"created_at": string,"data": NonNullable<Json>,"event": string,"id": string,"idem_key": string,"link": string | null,"mandatory": boolean,"read_at": string | null,"title": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "body"?: string | null,"created_at"?: string,"data"?: NonNullable<Json>,"event": string,"id"?: string,"idem_key": string,"link"?: string | null,"mandatory"?: boolean,"read_at"?: string | null,"title": string,"user_id": string
                  }
                  Update: {
                    "body"?: string | null,"created_at"?: string,"data"?: NonNullable<Json>,"event"?: string,"id"?: string,"idem_key"?: string,"link"?: string | null,"mandatory"?: boolean,"read_at"?: string | null,"title"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"outreach_activities": {
                  Row: {
                    "channel": string,"created_at": string,"created_by": string,"creator_id": string,"direction": string,"follow_up_done_at": string | null,"id": string,"next_follow_up_at": string | null,"notes": string | null,"outcome": string
                  }
                  ComputedFields: never
                  Insert: {
                    "channel": string,"created_at"?: string,"created_by"?: string,"creator_id": string,"direction"?: string,"follow_up_done_at"?: string | null,"id"?: string,"next_follow_up_at"?: string | null,"notes"?: string | null,"outcome": string
                  }
                  Update: {
                    "channel"?: string,"created_at"?: string,"created_by"?: string,"creator_id"?: string,"direction"?: string,"follow_up_done_at"?: string | null,"id"?: string,"next_follow_up_at"?: string | null,"notes"?: string | null,"outcome"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "outreach_activities_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"payout_batches": {
                  Row: {
                    "approved_at": string | null,"approved_by": string | null,"cancelled_reason": string | null,"created_at": string,"created_by": string,"export_count": number,"exported_at": string | null,"exported_by": string | null,"filters": NonNullable<Json>,"id": string,"note": string | null,"ref": string,"second_approved_at": string | null,"second_approved_by": string | null,"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "approved_at"?: string | null,"approved_by"?: string | null,"cancelled_reason"?: string | null,"created_at"?: string,"created_by"?: string,"export_count"?: number,"exported_at"?: string | null,"exported_by"?: string | null,"filters"?: NonNullable<Json>,"id"?: string,"note"?: string | null,"ref": string,"second_approved_at"?: string | null,"second_approved_by"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "approved_at"?: string | null,"approved_by"?: string | null,"cancelled_reason"?: string | null,"created_at"?: string,"created_by"?: string,"export_count"?: number,"exported_at"?: string | null,"exported_by"?: string | null,"filters"?: NonNullable<Json>,"id"?: string,"note"?: string | null,"ref"?: string,"second_approved_at"?: string | null,"second_approved_by"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"payout_items": {
                  Row: {
                    "amount_paise": number,"entry_id": number,"payout_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paise": number,"entry_id": number,"payout_id": string
                  }
                  Update: {
                    "amount_paise"?: number,"entry_id"?: number,"payout_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "payout_items_entry_id_fkey"
      columns: ["entry_id"]
isOneToOne: false
      referencedRelation: "ledger_entries"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payout_items_payout_id_fkey"
      columns: ["payout_id"]
isOneToOne: false
      referencedRelation: "payouts"
      referencedColumns: ["id"]
    }
                  ]
                },"payouts": {
                  Row: {
                    "advice_path": string | null,"batch_id": string,"created_at": string,"creator_id": string,"eduwit_tds_paise": number,"gross_paise": number,"gst_base_paise": number,"gst_paise": number,"id": string,"needs_invoice": boolean,"net_paise": number,"paid_on": string | null,"payee": string,"ref": string,"sections": NonNullable<Json>,"status": string,"status_reason": string | null,"tds_paise": number,"updated_at": string,"utr": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "advice_path"?: string | null,"batch_id": string,"created_at"?: string,"creator_id": string,"eduwit_tds_paise"?: number,"gross_paise": number,"gst_base_paise"?: number,"gst_paise"?: number,"id"?: string,"needs_invoice"?: boolean,"net_paise": number,"paid_on"?: string | null,"payee"?: string,"ref": string,"sections"?: NonNullable<Json>,"status"?: string,"status_reason"?: string | null,"tds_paise"?: number,"updated_at"?: string,"utr"?: string | null
                  }
                  Update: {
                    "advice_path"?: string | null,"batch_id"?: string,"created_at"?: string,"creator_id"?: string,"eduwit_tds_paise"?: number,"gross_paise"?: number,"gst_base_paise"?: number,"gst_paise"?: number,"id"?: string,"needs_invoice"?: boolean,"net_paise"?: number,"paid_on"?: string | null,"payee"?: string,"ref"?: string,"sections"?: NonNullable<Json>,"status"?: string,"status_reason"?: string | null,"tds_paise"?: number,"updated_at"?: string,"utr"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "payouts_batch_id_fkey"
      columns: ["batch_id"]
isOneToOne: false
      referencedRelation: "payout_batches"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payouts_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"penalty_proposals": {
                  Row: {
                    "amount_paise": number,"created_at": string,"deal_id": string,"decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"deliverable_id": string | null,"forfeits": (string)[],"id": string,"key": string,"proposed_at": string,"reason": string,"rule_id": string,"status": string,"subject": string,"updated_at": string,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paise": number,"created_at"?: string,"deal_id": string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id"?: string | null,"forfeits"?: (string)[],"id"?: string,"key": string,"proposed_at": string,"reason": string,"rule_id": string,"status"?: string,"subject": string,"updated_at"?: string,"version_id": string
                  }
                  Update: {
                    "amount_paise"?: number,"created_at"?: string,"deal_id"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id"?: string | null,"forfeits"?: (string)[],"id"?: string,"key"?: string,"proposed_at"?: string,"reason"?: string,"rule_id"?: string,"status"?: string,"subject"?: string,"updated_at"?: string,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "penalty_proposals_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "penalty_proposals_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "penalty_proposals_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "deal_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"permissions": {
                  Row: {
                    "area": string,"key": string,"label": string
                  }
                  ComputedFields: never
                  Insert: {
                    "area": string,"key": string,"label": string
                  }
                  Update: {
                    "area"?: string,"key"?: string,"label"?: string
                  }
                  Relationships: [
                    
                  ]
                },"post_metric_snapshots": {
                  Row: {
                    "captured_at": string,"checkpoint": string,"clicks": number | null,"comments": number | null,"created_by": string | null,"deliverable_id": string,"id": number,"likes": number | null,"published_post_id": string,"reach": number | null,"saves": number | null,"screenshot_paths": (string)[],"shares": number | null,"source": string,"views": number | null,"watch_time_s": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "captured_at"?: string,"checkpoint": string,"clicks"?: number | null,"comments"?: number | null,"created_by"?: string | null,"deliverable_id": string,"id"?: never,"likes"?: number | null,"published_post_id": string,"reach"?: number | null,"saves"?: number | null,"screenshot_paths"?: (string)[],"shares"?: number | null,"source"?: string,"views"?: number | null,"watch_time_s"?: number | null
                  }
                  Update: {
                    "captured_at"?: string,"checkpoint"?: string,"clicks"?: number | null,"comments"?: number | null,"created_by"?: string | null,"deliverable_id"?: string,"id"?: never,"likes"?: number | null,"published_post_id"?: string,"reach"?: number | null,"saves"?: number | null,"screenshot_paths"?: (string)[],"shares"?: number | null,"source"?: string,"views"?: number | null,"watch_time_s"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "post_metric_snapshots_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_metric_snapshots_published_post_id_fkey"
      columns: ["published_post_id"]
isOneToOne: false
      referencedRelation: "published_posts"
      referencedColumns: ["id"]
    }
                  ]
                },"privacy_requests": {
                  Row: {
                    "creator_id": string,"decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"file_expires_at": string | null,"id": string,"kind": string,"plan": Json | null,"purge_on": string | null,"reason": string | null,"requested_at": string,"requested_by": string,"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "creator_id": string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"file_expires_at"?: string | null,"id"?: string,"kind": string,"plan"?: Json | null,"purge_on"?: string | null,"reason"?: string | null,"requested_at"?: string,"requested_by"?: string,"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "creator_id"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"file_expires_at"?: string | null,"id"?: string,"kind"?: string,"plan"?: Json | null,"purge_on"?: string | null,"reason"?: string | null,"requested_at"?: string,"requested_by"?: string,"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "privacy_requests_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"published_posts": {
                  Row: {
                    "created_at": string,"created_by": string | null,"deliverable_id": string,"disclosure_ok": boolean | null,"id": string,"live_url": string,"oembed": Json | null,"posted_on": string,"review_note": string | null,"verification": Json | null,"verification_status": string,"verified_at": string | null,"verified_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"deliverable_id": string,"disclosure_ok"?: boolean | null,"id"?: string,"live_url": string,"oembed"?: Json | null,"posted_on": string,"review_note"?: string | null,"verification"?: Json | null,"verification_status"?: string,"verified_at"?: string | null,"verified_by"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"deliverable_id"?: string,"disclosure_ok"?: boolean | null,"id"?: string,"live_url"?: string,"oembed"?: Json | null,"posted_on"?: string,"review_note"?: string | null,"verification"?: Json | null,"verification_status"?: string,"verified_at"?: string | null,"verified_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "published_posts_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    }
                  ]
                },"rate_hits": {
                  Row: {
                    "hits": number,"key": string,"window_start": string
                  }
                  ComputedFields: never
                  Insert: {
                    "hits"?: number,"key": string,"window_start": string
                  }
                  Update: {
                    "hits"?: number,"key"?: string,"window_start"?: string
                  }
                  Relationships: [
                    
                  ]
                },"reason_templates": {
                  Row: {
                    "active": boolean,"body": string,"id": string,"kind": string,"label": string,"position": number
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"body": string,"id"?: string,"kind": string,"label": string,"position"?: number
                  }
                  Update: {
                    "active"?: boolean,"body"?: string,"id"?: string,"kind"?: string,"label"?: string,"position"?: number
                  }
                  Relationships: [
                    
                  ]
                },"review_comments": {
                  Row: {
                    "author_id": string,"author_side": string,"body": string,"created_at": string,"deliverable_id": string,"id": string,"image_region": Json | null,"parent_id": string | null,"resolved_at": string | null,"resolved_by": string | null,"submission_id": string,"video_timestamp_ms": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id"?: string,"author_side": string,"body": string,"created_at"?: string,"deliverable_id": string,"id"?: string,"image_region"?: Json | null,"parent_id"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"submission_id": string,"video_timestamp_ms"?: number | null
                  }
                  Update: {
                    "author_id"?: string,"author_side"?: string,"body"?: string,"created_at"?: string,"deliverable_id"?: string,"id"?: string,"image_region"?: Json | null,"parent_id"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"submission_id"?: string,"video_timestamp_ms"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "review_comments_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "review_comments_parent_id_fkey"
      columns: ["parent_id"]
isOneToOne: false
      referencedRelation: "review_comments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "review_comments_submission_id_fkey"
      columns: ["submission_id"]
isOneToOne: false
      referencedRelation: "deliverable_submissions"
      referencedColumns: ["id"]
    }
                  ]
                },"revision_extensions": {
                  Row: {
                    "decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"deliverable_id": string,"fee_paise": number,"id": string,"reason": string,"requested_at": string,"requested_by": string | null,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id": string,"fee_paise"?: number,"id"?: string,"reason": string,"requested_at"?: string,"requested_by"?: string | null,"status"?: string
                  }
                  Update: {
                    "decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"deliverable_id"?: string,"fee_paise"?: number,"id"?: string,"reason"?: string,"requested_at"?: string,"requested_by"?: string | null,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "revision_extensions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    }
                  ]
                },"role_permissions": {
                  Row: {
                    "permission": string,"role": string
                  }
                  ComputedFields: never
                  Insert: {
                    "permission": string,"role": string
                  }
                  Update: {
                    "permission"?: string,"role"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "role_permissions_permission_fkey"
      columns: ["permission"]
isOneToOne: false
      referencedRelation: "permissions"
      referencedColumns: ["key"]
    }
                  ]
                },"saved_views": {
                  Row: {
                    "created_at": string,"filters": NonNullable<Json>,"id": string,"is_shared": boolean,"name": string,"owner_id": string,"scope": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"filters": NonNullable<Json>,"id"?: string,"is_shared"?: boolean,"name": string,"owner_id"?: string,"scope"?: string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"filters"?: NonNullable<Json>,"id"?: string,"is_shared"?: boolean,"name"?: string,"owner_id"?: string,"scope"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"scorecards": {
                  Row: {
                    "composite": number | null,"created_at": string,"created_by": string | null,"creator_id": string,"facts": NonNullable<Json>,"figures": NonNullable<Json>,"id": string,"kind": string,"period": string,"period_from": string,"period_to": string,"scores": NonNullable<Json>,"tier_after": string | null,"tier_before": string | null,"weights": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "composite"?: number | null,"created_at"?: string,"created_by"?: string | null,"creator_id": string,"facts": NonNullable<Json>,"figures"?: NonNullable<Json>,"id"?: string,"kind": string,"period": string,"period_from": string,"period_to": string,"scores": NonNullable<Json>,"tier_after"?: string | null,"tier_before"?: string | null,"weights": NonNullable<Json>
                  }
                  Update: {
                    "composite"?: number | null,"created_at"?: string,"created_by"?: string | null,"creator_id"?: string,"facts"?: NonNullable<Json>,"figures"?: NonNullable<Json>,"id"?: string,"kind"?: string,"period"?: string,"period_from"?: string,"period_to"?: string,"scores"?: NonNullable<Json>,"tier_after"?: string | null,"tier_before"?: string | null,"weights"?: NonNullable<Json>
                  }
                  Relationships: [
                    {
      foreignKeyName: "scorecards_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "scorecards_tier_after_fkey"
      columns: ["tier_after"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "scorecards_tier_before_fkey"
      columns: ["tier_before"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    }
                  ]
                },"setting_definitions": {
                  Row: {
                    "default_value": NonNullable<Json>,"description": string,"edit_permission": string,"grp": string,"json_schema": NonNullable<Json>,"key": string,"label": string,"needs_confirmation": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "default_value": NonNullable<Json>,"description": string,"edit_permission": string,"grp": string,"json_schema": NonNullable<Json>,"key": string,"label": string,"needs_confirmation"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "default_value"?: NonNullable<Json>,"description"?: string,"edit_permission"?: string,"grp"?: string,"json_schema"?: NonNullable<Json>,"key"?: string,"label"?: string,"needs_confirmation"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "setting_definitions_edit_permission_fkey"
      columns: ["edit_permission"]
isOneToOne: false
      referencedRelation: "permissions"
      referencedColumns: ["key"]
    }
                  ]
                },"settings": {
                  Row: {
                    "confirmed_at": string | null,"confirmed_by": string | null,"key": string,"updated_at": string,"updated_by": string | null,"value": NonNullable<Json>,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "confirmed_at"?: string | null,"confirmed_by"?: string | null,"key": string,"updated_at"?: string,"updated_by"?: string | null,"value": NonNullable<Json>,"version"?: number
                  }
                  Update: {
                    "confirmed_at"?: string | null,"confirmed_by"?: string | null,"key"?: string,"updated_at"?: string,"updated_by"?: string | null,"value"?: NonNullable<Json>,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "settings_key_fkey"
      columns: ["key"]
isOneToOne: true
      referencedRelation: "setting_definitions"
      referencedColumns: ["key"]
    }
                  ]
                },"settings_versions": {
                  Row: {
                    "actor_id": string | null,"at": string,"id": number,"key": string,"reason": string,"value": NonNullable<Json>,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "actor_id"?: string | null,"at"?: string,"id"?: never,"key": string,"reason": string,"value": NonNullable<Json>,"version": number
                  }
                  Update: {
                    "actor_id"?: string | null,"at"?: string,"id"?: never,"key"?: string,"reason"?: string,"value"?: NonNullable<Json>,"version"?: number
                  }
                  Relationships: [
                    
                  ]
                },"sign_in_log": {
                  Row: {
                    "at": string,"email": string | null,"id": number,"ip": unknown,"method": string,"outcome": string,"portal": string,"reason": string | null,"user_agent": string | null,"user_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "at"?: string,"email"?: string | null,"id"?: never,"ip"?: unknown,"method": string,"outcome": string,"portal": string,"reason"?: string | null,"user_agent"?: string | null,"user_id"?: string | null
                  }
                  Update: {
                    "at"?: string,"email"?: string | null,"id"?: never,"ip"?: unknown,"method"?: string,"outcome"?: string,"portal"?: string,"reason"?: string | null,"user_agent"?: string | null,"user_id"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"signatures": {
                  Row: {
                    "consent_text": string,"consent_version": number,"contract_id": string,"document_sha256": string,"geo": Json | null,"id": string,"ip": unknown,"otp_channel": string,"otp_reference": string,"signed_at": string,"signed_at_ist": string,"signer_designation": string | null,"signer_name": string,"signer_role": string,"signer_user_id": string,"user_agent": string | null,"version_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "consent_text": string,"consent_version": number,"contract_id": string,"document_sha256": string,"geo"?: Json | null,"id"?: string,"ip"?: unknown,"otp_channel": string,"otp_reference": string,"signed_at"?: string,"signed_at_ist"?: string,"signer_designation"?: string | null,"signer_name": string,"signer_role": string,"signer_user_id": string,"user_agent"?: string | null,"version_id": string
                  }
                  Update: {
                    "consent_text"?: string,"consent_version"?: number,"contract_id"?: string,"document_sha256"?: string,"geo"?: Json | null,"id"?: string,"ip"?: unknown,"otp_channel"?: string,"otp_reference"?: string,"signed_at"?: string,"signed_at_ist"?: string,"signer_designation"?: string | null,"signer_name"?: string,"signer_role"?: string,"signer_user_id"?: string,"user_agent"?: string | null,"version_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "signatures_consent_version_fkey"
      columns: ["consent_version"]
isOneToOne: false
      referencedRelation: "consent_texts"
      referencedColumns: ["version"]
    },{
      foreignKeyName: "signatures_contract_id_fkey"
      columns: ["contract_id"]
isOneToOne: false
      referencedRelation: "contracts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "signatures_version_id_fkey"
      columns: ["version_id"]
isOneToOne: false
      referencedRelation: "contract_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"staff_profiles": {
                  Row: {
                    "created_at": string,"created_by": string | null,"email": string,"full_name": string,"is_signatory": boolean,"last_seen_at": string | null,"signatory_designation": string | null,"status": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"email": string,"full_name": string,"is_signatory"?: boolean,"last_seen_at"?: string | null,"signatory_designation"?: string | null,"status"?: string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"email"?: string,"full_name"?: string,"is_signatory"?: boolean,"last_seen_at"?: string | null,"signatory_designation"?: string | null,"status"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"staff_role_grants": {
                  Row: {
                    "granted_at": string,"granted_by": string | null,"role": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "granted_at"?: string,"granted_by"?: string | null,"role": string,"user_id": string
                  }
                  Update: {
                    "granted_at"?: string,"granted_by"?: string | null,"role"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "staff_role_grants_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "staff_profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"stage_mappings": {
                  Row: {
                    "active": boolean,"conditions": NonNullable<Json>,"created_at": string,"creator_stage": string | null,"flag": string | null,"id": string,"priority": number,"reason_category": string | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"conditions": NonNullable<Json>,"created_at"?: string,"creator_stage"?: string | null,"flag"?: string | null,"id"?: string,"priority": number,"reason_category"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "active"?: boolean,"conditions"?: NonNullable<Json>,"created_at"?: string,"creator_stage"?: string | null,"flag"?: string | null,"id"?: string,"priority"?: number,"reason_category"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"sync_state": {
                  Row: {
                    "detail": NonNullable<Json>,"key": string,"updated_at": string,"watermark": string
                  }
                  ComputedFields: never
                  Insert: {
                    "detail"?: NonNullable<Json>,"key": string,"updated_at"?: string,"watermark": string
                  }
                  Update: {
                    "detail"?: NonNullable<Json>,"key"?: string,"updated_at"?: string,"watermark"?: string
                  }
                  Relationships: [
                    
                  ]
                },"tasks": {
                  Row: {
                    "assignee_id": string | null,"completed_at": string | null,"created_at": string,"created_by": string,"description": string | null,"due_at": string | null,"id": string,"priority": string,"related_id": string | null,"related_type": string | null,"status": string,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "assignee_id"?: string | null,"completed_at"?: string | null,"created_at"?: string,"created_by"?: string,"description"?: string | null,"due_at"?: string | null,"id"?: string,"priority"?: string,"related_id"?: string | null,"related_type"?: string | null,"status"?: string,"title": string,"updated_at"?: string
                  }
                  Update: {
                    "assignee_id"?: string | null,"completed_at"?: string | null,"created_at"?: string,"created_by"?: string,"description"?: string | null,"due_at"?: string | null,"id"?: string,"priority"?: string,"related_id"?: string | null,"related_type"?: string | null,"status"?: string,"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "tasks_assignee_id_fkey"
      columns: ["assignee_id"]
isOneToOne: false
      referencedRelation: "staff_profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"tds_certificates": {
                  Row: {
                    "creator_id": string,"file_path": string,"fy": string,"id": string,"quarter": string,"uploaded_at": string,"uploaded_by": string
                  }
                  ComputedFields: never
                  Insert: {
                    "creator_id": string,"file_path": string,"fy": string,"id"?: string,"quarter": string,"uploaded_at"?: string,"uploaded_by"?: string
                  }
                  Update: {
                    "creator_id"?: string,"file_path"?: string,"fy"?: string,"id"?: string,"quarter"?: string,"uploaded_at"?: string,"uploaded_by"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "tds_certificates_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"tds_records": {
                  Row: {
                    "amount_paise": number,"base_paise": number,"borne_by": string,"created_at": string,"creator_id": string,"fy": string,"id": string,"paid_on": string,"payout_id": string,"quarter": string,"rate_bps": number,"section": string,"taxable_paise": number
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paise": number,"base_paise": number,"borne_by": string,"created_at"?: string,"creator_id": string,"fy": string,"id"?: string,"paid_on": string,"payout_id": string,"quarter": string,"rate_bps": number,"section": string,"taxable_paise": number
                  }
                  Update: {
                    "amount_paise"?: number,"base_paise"?: number,"borne_by"?: string,"created_at"?: string,"creator_id"?: string,"fy"?: string,"id"?: string,"paid_on"?: string,"payout_id"?: string,"quarter"?: string,"rate_bps"?: number,"section"?: string,"taxable_paise"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "tds_records_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tds_records_payout_id_fkey"
      columns: ["payout_id"]
isOneToOne: false
      referencedRelation: "payouts"
      referencedColumns: ["id"]
    }
                  ]
                },"tds_sections": {
                  Row: {
                    "borne_by": string,"code": string,"components": (string)[],"confirmed_by_ca": boolean,"fy_threshold_paise": number | null,"label": string,"no_pan_rate_bps": number,"position": number,"rate_bps": number,"single_threshold_paise": number | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "borne_by"?: string,"code": string,"components": (string)[],"confirmed_by_ca"?: boolean,"fy_threshold_paise"?: number | null,"label": string,"no_pan_rate_bps": number,"position"?: number,"rate_bps": number,"single_threshold_paise"?: number | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "borne_by"?: string,"code"?: string,"components"?: (string)[],"confirmed_by_ca"?: boolean,"fy_threshold_paise"?: number | null,"label"?: string,"no_pan_rate_bps"?: number,"position"?: number,"rate_bps"?: number,"single_threshold_paise"?: number | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"template_clauses": {
                  Row: {
                    "clause_id": string,"condition": string | null,"position": number,"template_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "clause_id": string,"condition"?: string | null,"position": number,"template_id": string
                  }
                  Update: {
                    "clause_id"?: string,"condition"?: string | null,"position"?: number,"template_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "template_clauses_clause_id_fkey"
      columns: ["clause_id"]
isOneToOne: false
      referencedRelation: "clauses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "template_clauses_template_id_fkey"
      columns: ["template_id"]
isOneToOne: false
      referencedRelation: "contract_templates"
      referencedColumns: ["id"]
    }
                  ]
                },"terms_acceptances": {
                  Row: {
                    "accepted_at": string,"id": number,"ip": unknown,"terms_version_id": string,"user_agent": string | null,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accepted_at"?: string,"id"?: never,"ip"?: unknown,"terms_version_id": string,"user_agent"?: string | null,"user_id": string
                  }
                  Update: {
                    "accepted_at"?: string,"id"?: never,"ip"?: unknown,"terms_version_id"?: string,"user_agent"?: string | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "terms_acceptances_terms_version_id_fkey"
      columns: ["terms_version_id"]
isOneToOne: false
      referencedRelation: "terms_versions"
      referencedColumns: ["id"]
    }
                  ]
                },"terms_versions": {
                  Row: {
                    "body": string,"created_at": string,"created_by": string | null,"effective_at": string,"id": string,"kind": string,"title": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "body": string,"created_at"?: string,"created_by"?: string | null,"effective_at"?: string,"id"?: string,"kind": string,"title": string,"version": number
                  }
                  Update: {
                    "body"?: string,"created_at"?: string,"created_by"?: string | null,"effective_at"?: string,"id"?: string,"kind"?: string,"title"?: string,"version"?: number
                  }
                  Relationships: [
                    
                  ]
                },"thread_reads": {
                  Row: {
                    "last_read_at": string,"thread_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "last_read_at"?: string,"thread_id": string,"user_id": string
                  }
                  Update: {
                    "last_read_at"?: string,"thread_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "thread_reads_thread_id_fkey"
      columns: ["thread_id"]
isOneToOne: false
      referencedRelation: "threads"
      referencedColumns: ["id"]
    }
                  ]
                },"threads": {
                  Row: {
                    "created_at": string,"creator_id": string | null,"entity_id": string,"entity_type": string,"id": string,"last_message_at": string | null,"staff_only": boolean
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"creator_id"?: string | null,"entity_id": string,"entity_type": string,"id"?: string,"last_message_at"?: string | null,"staff_only"?: boolean
                  }
                  Update: {
                    "created_at"?: string,"creator_id"?: string | null,"entity_id"?: string,"entity_type"?: string,"id"?: string,"last_message_at"?: string | null,"staff_only"?: boolean
                  }
                  Relationships: [
                    {
      foreignKeyName: "threads_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"tier_history": {
                  Row: {
                    "created_at": string,"created_by": string | null,"creator_id": string,"from_tier": string | null,"id": number,"note": string | null,"reason": string,"scorecard_id": string | null,"to_tier": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"creator_id": string,"from_tier"?: string | null,"id"?: never,"note"?: string | null,"reason": string,"scorecard_id"?: string | null,"to_tier"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"creator_id"?: string,"from_tier"?: string | null,"id"?: never,"note"?: string | null,"reason"?: string,"scorecard_id"?: string | null,"to_tier"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "tier_history_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tier_history_from_tier_fkey"
      columns: ["from_tier"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tier_history_scorecard_id_fkey"
      columns: ["scorecard_id"]
isOneToOne: false
      referencedRelation: "scorecards"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tier_history_to_tier_fkey"
      columns: ["to_tier"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    }
                  ]
                },"tiers": {
                  Row: {
                    "active": boolean,"benefits": NonNullable<Json>,"created_at": string,"entry_rules": NonNullable<Json>,"id": string,"name": string,"rank": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"benefits"?: NonNullable<Json>,"created_at"?: string,"entry_rules"?: NonNullable<Json>,"id"?: string,"name": string,"rank": number,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"benefits"?: NonNullable<Json>,"created_at"?: string,"entry_rules"?: NonNullable<Json>,"id"?: string,"name"?: string,"rank"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"tracking_links": {
                  Row: {
                    "active": boolean,"campaign_id": string | null,"code": string,"created_at": string,"created_by": string | null,"creator_id": string,"custom_url": string | null,"deal_id": string | null,"deliverable_id": string | null,"destination": string,"id": string,"label": string | null,"platform": string | null,"programme_id": number | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"campaign_id"?: string | null,"code": string,"created_at"?: string,"created_by"?: string | null,"creator_id": string,"custom_url"?: string | null,"deal_id"?: string | null,"deliverable_id"?: string | null,"destination": string,"id"?: string,"label"?: string | null,"platform"?: string | null,"programme_id"?: number | null,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"campaign_id"?: string | null,"code"?: string,"created_at"?: string,"created_by"?: string | null,"creator_id"?: string,"custom_url"?: string | null,"deal_id"?: string | null,"deliverable_id"?: string | null,"destination"?: string,"id"?: string,"label"?: string | null,"platform"?: string | null,"programme_id"?: number | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "tracking_links_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tracking_links_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tracking_links_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tracking_links_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    }
                  ]
                },"trusted_devices": {
                  Row: {
                    "created_at": string,"expires_at": string,"id": string,"label": string | null,"last_used_at": string | null,"revoked_at": string | null,"token_hash": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"expires_at": string,"id"?: string,"label"?: string | null,"last_used_at"?: string | null,"revoked_at"?: string | null,"token_hash": string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"expires_at"?: string,"id"?: string,"label"?: string | null,"last_used_at"?: string | null,"revoked_at"?: string | null,"token_hash"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"user_sessions": {
                  Row: {
                    "auth_method": string | null,"created_at": string,"ip": unknown,"kind": string,"last_seen_at": string,"revoke_reason": string | null,"revoked_at": string | null,"revoked_by": string | null,"session_id": string,"user_agent": string | null,"user_id": string,"verified_at": string | null,"verified_via": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "auth_method"?: string | null,"created_at"?: string,"ip"?: unknown,"kind": string,"last_seen_at"?: string,"revoke_reason"?: string | null,"revoked_at"?: string | null,"revoked_by"?: string | null,"session_id": string,"user_agent"?: string | null,"user_id": string,"verified_at"?: string | null,"verified_via"?: string | null
                  }
                  Update: {
                    "auth_method"?: string | null,"created_at"?: string,"ip"?: unknown,"kind"?: string,"last_seen_at"?: string,"revoke_reason"?: string | null,"revoked_at"?: string | null,"revoked_by"?: string | null,"session_id"?: string,"user_agent"?: string | null,"user_id"?: string,"verified_at"?: string | null,"verified_via"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"webhook_deliveries": {
                  Row: {
                    "attempts": number,"created_at": string,"delivered_at": string | null,"endpoint_id": string,"event": string,"event_id": string,"id": number,"last_error": string | null,"last_status": number | null,"next_attempt_at": string,"payload": NonNullable<Json>,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempts"?: number,"created_at"?: string,"delivered_at"?: string | null,"endpoint_id": string,"event": string,"event_id": string,"id"?: never,"last_error"?: string | null,"last_status"?: number | null,"next_attempt_at"?: string,"payload": NonNullable<Json>,"status"?: string
                  }
                  Update: {
                    "attempts"?: number,"created_at"?: string,"delivered_at"?: string | null,"endpoint_id"?: string,"event"?: string,"event_id"?: string,"id"?: never,"last_error"?: string | null,"last_status"?: number | null,"next_attempt_at"?: string,"payload"?: NonNullable<Json>,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "webhook_deliveries_endpoint_id_fkey"
      columns: ["endpoint_id"]
isOneToOne: false
      referencedRelation: "webhook_endpoints"
      referencedColumns: ["id"]
    }
                  ]
                },"webhook_endpoints": {
                  Row: {
                    "active": boolean,"created_at": string,"created_by": string,"description": string | null,"events": (string)[],"failing_since": string | null,"id": string,"last_success_at": string | null,"secret_enc": string,"updated_at": string,"url": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"created_by"?: string,"description"?: string | null,"events": (string)[],"failing_since"?: string | null,"id"?: string,"last_success_at"?: string | null,"secret_enc": string,"updated_at"?: string,"url": string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"created_by"?: string,"description"?: string | null,"events"?: (string)[],"failing_since"?: string | null,"id"?: string,"last_success_at"?: string | null,"secret_enc"?: string,"updated_at"?: string,"url"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            "an_clicks_daily": {
                  Row: {
                    "bot_clicks": number | null,"campaign_id": string | null,"clicks": number | null,"content_type": string | null,"creator_id": string | null,"day": string | null,"deal_id": string | null,"deal_model": string | null,"deliverable_id": string | null,"link_id": string | null,"platform": string | null,"programme_id": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "link_clicks_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tracking_links_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tracking_links_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tracking_links_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    }
                  ]
                },"an_leads": {
                  Row: {
                    "allocated": boolean | null,"applied": boolean | null,"attribution_id": string | null,"campaign_id": string | null,"content_type": string | null,"creator_id": string | null,"credited": boolean | null,"day": string | null,"deal_id": string | null,"deal_model": string | null,"deliverable_id": string | null,"duplicate": boolean | null,"enrolled": boolean | null,"is_test": boolean | null,"junk": boolean | null,"link_id": string | null,"platform": string | null,"programme_id": number | null,"qualified": boolean | null,"student_lead_id": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "lead_attributions_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    }
                  ]
                },"an_leads_live": {
                  Row: {
                    "allocated": boolean | null,"applied": boolean | null,"attribution_id": string | null,"campaign_id": string | null,"content_type": string | null,"creator_id": string | null,"credited": boolean | null,"day": string | null,"deal_id": string | null,"deal_model": string | null,"deliverable_id": string | null,"duplicate": boolean | null,"enrolled": boolean | null,"is_test": boolean | null,"junk": boolean | null,"link_id": string | null,"platform": string | null,"programme_id": number | null,"qualified": boolean | null,"student_lead_id": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "lead_attributions_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    }
                  ]
                },"an_revenue": {
                  Row: {
                    "attribution_id": string | null,"campaign_id": string | null,"content_type": string | null,"creator_id": string | null,"day": string | null,"deal_id": string | null,"deal_model": string | null,"deliverable_id": string | null,"enrollment_ref": string | null,"expected_net_paise": number | null,"is_test": boolean | null,"link_id": string | null,"platform": string | null,"programme_id": number | null,"received_net_paise": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "lead_attributions_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    }
                  ]
                },"an_spend_daily": {
                  Row: {
                    "accrued_paise": number | null,"campaign_id": string | null,"content_type": string | null,"creator_id": string | null,"day": string | null,"deal_id": string | null,"deal_model": string | null,"deliverable_id": string | null,"k": string | null,"link_id": string | null,"platform": string | null,"programme_id": number | null,"type": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "lead_attributions_deliverable_id_fkey"
      columns: ["deliverable_id"]
isOneToOne: false
      referencedRelation: "deliverables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "lead_attributions_link_id_fkey"
      columns: ["link_id"]
isOneToOne: false
      referencedRelation: "tracking_links"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            "actor_role":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"agency_account_link":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"agency_can":
{ Args: { "p_creator": string,"p_grant": string }; Returns: boolean
                           },
"agency_creators":
{ Args: Record<PropertyKey, never>; Returns: {
              "avatar_path": string,"can_act_deliverables": boolean,"can_negotiate_sign": boolean,"can_view": boolean,"can_view_earnings": boolean,"creator_id": string,"creator_status": string,"display_name": string,"handle": string,"link_id": string,"link_status": string,"requested_at": string
            }[]
                           },
"agency_link_request":
{ Args: { "p_agency": string,"p_creator": string }; Returns: string
                           },
"agency_link_request_by_handle":
{ Args: { "p_agency": string,"p_handle": string }; Returns: string
                           },
"agency_link_respond":
{ Args: { "p_accept": boolean,"p_deliverables": boolean,"p_earnings": boolean,"p_link": string,"p_negotiate": boolean,"p_view": boolean }; Returns: undefined
                           },
"agency_link_revoke":
{ Args: { "p_link": string,"p_reason": string }; Returns: undefined
                           },
"agency_member_add":
{ Args: { "p_agency": string,"p_email": string,"p_full_name": string,"p_role"?: string }; Returns: string
                           },
"agency_member_remove":
{ Args: { "p_member": string }; Returns: undefined
                           },
"agency_save":
{ Args: { "p": Json }; Returns: string
                           },
"agency_set_status":
{ Args: { "p_agency": string,"p_reason": string,"p_status": string }; Returns: undefined
                           },
"an_bucket":
{ Args: { "p_bucket": string,"p_day": string }; Returns: string
                           },
"an_stage_rank":
{ Args: { "p": string }; Returns: number
                           },
"analytics_creators":
{ Args: { "p": Json }; Returns: Json
                           },
"analytics_finance":
{ Args: { "p": Json }; Returns: Json
                           },
"analytics_health":
{ Args: { "p": Json }; Returns: Json
                           },
"analytics_meta":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"analytics_operations":
{ Args: { "p_campaign"?: string }; Returns: Json
                           },
"analytics_refresh":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"analytics_spend":
{ Args: { "p": Json }; Returns: Json
                           },
"analytics_totals":
{ Args: { "p": Json }; Returns: Json
                           },
"announcement_audience":
{ Args: { "p_segment": Json }; Returns: {
              "creator_id": string,"user_id": string
            }[]
                           },
"announcement_audience_count":
{ Args: { "p_segment": Json }; Returns: number
                           },
"announcement_cancel":
{ Args: { "p_id": string }; Returns: undefined
                           },
"announcement_save":
{ Args: { "p": Json }; Returns: string
                           },
"announcements_list":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"announcements_send_due":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"application_deal_source":
{ Args: { "p_app": string }; Returns: Json
                           },
"application_detail":
{ Args: { "p_app": string }; Returns: Json
                           },
"application_message":
{ Args: { "p_app": string,"p_body": string }; Returns: string
                           },
"application_notify":
{ Args: { "p_app": string,"p_body": string,"p_event": string,"p_title": string,"p_to": string }; Returns: undefined
                           },
"application_reject":
{ Args: { "p_app": string,"p_reason": string }; Returns: undefined
                           },
"application_shortlist":
{ Args: { "p_app": string }; Returns: undefined
                           },
"application_side":
{ Args: { "p_creator": string }; Returns: string
                           },
"application_withdraw":
{ Args: { "p_app": string }; Returns: undefined
                           },
"applications_list":
{ Args: { "p_campaign"?: string,"p_status"?: (string)[] }; Returns: {
              "campaign_id": string,"campaign_name": string,"created_at": string,"creator_id": string,"display_name": string,"followers": number,"handle": string,"id": string,"open_offer_from": string,"source": string,"status": string,"updated_at": string
            }[]
                           },
"approvals_queue":
{ Args: Record<PropertyKey, never>; Returns: {
              "creator_id": string,"display_name": string,"followers": number,"handle": string,"kyc_status": string,"owner_name": string,"source": string,"submitted_at": string
            }[]
                           },
"asci_items":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"attribution_override":
{ Args: { "p": Json }; Returns: string
                           },
"attribution_overview":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"audit":
{ Args: { "p_action": string,"p_after"?: Json,"p_before"?: Json,"p_entity_id": string,"p_entity_type": string }; Returns: undefined
                           },
"auth_user_id_by_email":
{ Args: { "p_email": string }; Returns: string
                           },
"avatar_set":
{ Args: { "p_creator": string,"p_path"?: string }; Returns: undefined
                           },
"banned_claim_save":
{ Args: { "p": Json }; Returns: string
                           },
"banned_claims_active":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"bootstrap_super_admin":
{ Args: { "p_designation": string,"p_email": string,"p_full_name": string }; Returns: string
                           },
"brief_acknowledge":
{ Args: { "p_brief": string,"p_version": string }; Returns: undefined
                           },
"brief_asset_allowed":
{ Args: { "p_brief": string,"p_path": string }; Returns: boolean
                           },
"brief_create":
{ Args: { "p": Json }; Returns: string
                           },
"brief_detail":
{ Args: { "p_brief": string }; Returns: Json
                           },
"brief_publish":
{ Args: { "p_brief": string,"p_note"?: string }; Returns: string
                           },
"brief_question_add":
{ Args: { "p_body": string,"p_brief": string,"p_parent"?: string }; Returns: string
                           },
"brief_save":
{ Args: { "p_brief": string,"p_content": Json }; Returns: undefined
                           },
"brief_source":
{ Args: { "p_deal": string }; Returns: Json
                           },
"brief_template_archive":
{ Args: { "p_archived": boolean,"p_template": string }; Returns: undefined
                           },
"brief_template_save":
{ Args: { "p": Json }; Returns: string
                           },
"briefs_list":
{ Args: { "p": Json }; Returns: Json
                           },
"campaign_apply":
{ Args: { "p_campaign": string,"p_creator": string,"p_pitch": string,"p_samples": (string)[],"p_terms": Json }; Returns: string
                           },
"campaign_attribution_save":
{ Args: { "p_campaign": string,"p_message": string,"p_model": string }; Returns: undefined
                           },
"campaign_for_creator":
{ Args: { "p_campaign": string,"p_creator"?: string }; Returns: Json
                           },
"campaign_invite":
{ Args: { "p_campaign": string,"p_creators": (string)[],"p_message": string }; Returns: number
                           },
"campaign_programmes_view":
{ Args: { "p_campaign": string }; Returns: {
              "available": boolean,"fee_total": number,"id": number,"level": string,"mode": string,"program_name": string,"specialization": string,"university": string
            }[]
                           },
"campaign_public":
{ Args: { "c": Omit<Database["inf"]['Tables']["campaigns"]['Row'], Database["inf"]['Tables']["campaigns"]['ComputedFields']>,"p_creator": string }; Returns: Json
                           },
"campaign_save":
{ Args: { "p": Json }; Returns: string
                           },
"campaign_set_status":
{ Args: { "p_campaign": string,"p_status": string }; Returns: undefined
                           },
"campaign_stats":
{ Args: { "p_campaign": string }; Returns: Json
                           },
"can_edit_creator":
{ Args: { "p_creator": string }; Returns: boolean
                           },
"can_negotiate_for":
{ Args: { "p_creator": string }; Returns: boolean
                           },
"can_see_campaign":
{ Args: { "p_campaign": string }; Returns: boolean
                           },
"can_view_creator":
{ Args: { "p_creator": string }; Returns: boolean
                           },
"can_view_deal_of":
{ Args: { "p_creator": string }; Returns: boolean
                           },
"can_view_earnings":
{ Args: { "p_creator": string }; Returns: boolean
                           },
"catalog_programmes_search":
{ Args: { "p_limit"?: number,"p_q": string }; Returns: {
              "fee_total": number,"id": number,"level": string,"mode": string,"program_name": string,"specialization": string,"university": string
            }[]
                           },
"change_request_create":
{ Args: { "p": Json,"p_contract": string }; Returns: string
                           },
"change_request_decide":
{ Args: { "p_note": string,"p_request": string,"p_status": string }; Returns: undefined
                           },
"change_request_withdraw":
{ Args: { "p_request": string }; Returns: undefined
                           },
"clause_archive":
{ Args: { "p_archived": boolean,"p_clause": string }; Returns: undefined
                           },
"clause_history":
{ Args: { "p_clause": string }; Returns: Json
                           },
"clause_library":
{ Args: { "p_include_archived"?: boolean }; Returns: Json
                           },
"clause_mark_reviewed":
{ Args: { "p_clause": string,"p_version": number }; Returns: undefined
                           },
"clause_save":
{ Args: { "p": Json }; Returns: string
                           },
"click_log":
{ Args: { "p": Json }; Returns: number
                           },
"code_hash":
{ Args: { "p_code": string,"p_salt": string,"p_user": string }; Returns: string
                           },
"comm_daily":
{ Args: Record<PropertyKey, never>; Returns: undefined
                           },
"commission_estimate":
{ Args: { "p_campaign": string }; Returns: number
                           },
"commission_receipts_sync":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"comp_config_errors":
{ Args: { "p": Json }; Returns: (string)[]
                           },
"comp_config_schema":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"comp_config_valid":
{ Args: { "p": Json }; Returns: boolean
                           },
"comp_context":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"comp_run_record":
{ Args: { "p_as_of": string,"p_deal": string,"p_kind": string,"p_summary": Json,"p_version": string }; Returns: number
                           },
"compliance_facts":
{ Args: { "p_creator": string }; Returns: Json
                           },
"compliance_override":
{ Args: { "p_check": string,"p_reason": string }; Returns: undefined
                           },
"compliance_record":
{ Args: { "p_checks": Json,"p_submission": string }; Returns: undefined
                           },
"config_hash":
{ Args: { "p": Json }; Returns: string
                           },
"content_notify":
{ Args: { "p_admin_link": string,"p_body": string,"p_creator_link": string,"p_deal": string,"p_event": string,"p_key": string,"p_title": string,"p_to": string }; Returns: undefined
                           },
"content_remind":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"content_side":
{ Args: { "p_deal": string }; Returns: string
                           },
"contract_comment_add":
{ Args: { "p_body": string,"p_clause": string,"p_contract": string,"p_parent"?: string }; Returns: string
                           },
"contract_comment_resolve":
{ Args: { "p_comment": string }; Returns: undefined
                           },
"contract_create":
{ Args: { "p": Json }; Returns: string
                           },
"contract_detail":
{ Args: { "p_contract": string }; Returns: Json
                           },
"contract_file_record":
{ Args: { "p_contract": string,"p_path": string,"p_sha256": string,"p_version": string }; Returns: undefined
                           },
"contract_flag":
{ Args: { "p_contract": string,"p_reason": string }; Returns: undefined
                           },
"contract_integrity":
{ Args: { "p_contract": string }; Returns: Json
                           },
"contract_notify":
{ Args: { "p_body": string,"p_contract": string,"p_event": string,"p_title": string,"p_to": string }; Returns: undefined
                           },
"contract_send":
{ Args: { "p_contract": string }; Returns: undefined
                           },
"contract_set_ready":
{ Args: { "p_contract": string }; Returns: undefined
                           },
"contract_set_status":
{ Args: { "p_contract": string,"p_reason"?: string,"p_status": string }; Returns: undefined
                           },
"contract_side":
{ Args: { "p_contract": string }; Returns: string
                           },
"contract_sign":
{ Args: { "p_code": string,"p_consent_version": number,"p_contract": string,"p_ip": string,"p_name": string,"p_sha256": string,"p_user": string,"p_user_agent": string,"p_version": string }; Returns: Json
                           },
"contract_sign_code_issue":
{ Args: { "p_channel": string,"p_contract": string,"p_user": string }; Returns: Json
                           },
"contract_signer_role":
{ Args: { "p_contract": string,"p_user": string }; Returns: string
                           },
"contract_source":
{ Args: { "p_deal": string }; Returns: Json
                           },
"contract_version_add":
{ Args: { "p_content": Json,"p_contract": string,"p_html": string,"p_missing"?: (string)[],"p_note"?: string,"p_overrides": Json,"p_resolve"?: Json }; Returns: string
                           },
"contract_version_html":
{ Args: { "p_version": string }; Returns: Json
                           },
"contract_writer":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"contracts_list":
{ Args: { "p": Json }; Returns: Json
                           },
"contracts_remind":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"course_content":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"course_submit":
{ Args: { "p_answers": Json }; Returns: Json
                           },
"creator_account_link":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"creator_approve_internal":
{ Args: { "p_by": string,"p_creator": string }; Returns: undefined
                           },
"creator_contact_add":
{ Args: { "p_creator": string,"p_email": string,"p_kind": string,"p_label": string,"p_phone": string }; Returns: string
                           },
"creator_contact_delete":
{ Args: { "p_creator": string,"p_id": string }; Returns: undefined
                           },
"creator_dashboard":
{ Args: { "p": Json,"p_creator": string }; Returns: Json
                           },
"creator_delete_draft":
{ Args: { "p_creator": string }; Returns: undefined
                           },
"creator_earnings":
{ Args: { "p_creator": string }; Returns: Json
                           },
"creator_import":
{ Args: { "p_dry_run"?: boolean,"p_file_name": string,"p_invalid"?: Json,"p_rows": Json }; Returns: Json
                           },
"creator_list":
{ Args: { "p": Json }; Returns: Json
                           },
"creator_profile_update":
{ Args: { "p": Json,"p_creator": string }; Returns: undefined
                           },
"creator_review":
{ Args: { "p_creator": string,"p_decision": string,"p_reason": string }; Returns: undefined
                           },
"creator_rows":
{ Args: { "p": Json }; Returns: {
              "city": string,"display_name": string,"email": string,"followers": number,"handle": string,"has_account": boolean,"id": string,"is_blocked": boolean,"languages": (string)[],"last_activity_at": string,"last_contacted_at": string,"next_follow_up_at": string,"niches": (string)[],"owner_id": string,"owner_name": string,"pipeline_stage": string,"platforms": (string)[],"state": string,"status": string,"tags": (string)[],"tier_id": string,"tier_name": string,"updated_at": string
            }[]
                           },
"creator_save":
{ Args: { "p": Json }; Returns: string
                           },
"creator_scorecards":
{ Args: { "p_creator": string }; Returns: Json
                           },
"creator_self_signup":
{ Args: { "p": Json }; Returns: Json
                           },
"creator_set_blocked":
{ Args: { "p_blocked": boolean,"p_creator": string,"p_reason": string }; Returns: undefined
                           },
"creator_set_stage":
{ Args: { "p_creator": string,"p_stage": string }; Returns: undefined
                           },
"creator_stage_counts":
{ Args: { "p": Json }; Returns: {
              "n": number,"stage": string
            }[]
                           },
"creators_bulk":
{ Args: { "p_action": string,"p_ids": (string)[],"p_value": string }; Returns: number
                           },
"creators_flag_dormant":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"creators_invite":
{ Args: { "p_ids": (string)[] }; Returns: {
              "creator_id": string,"display_name": string,"email": string
            }[]
                           },
"cron_dispatch":
{ Args: { "p_path": string }; Returns: undefined
                           },
"current_agency_id":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"current_agency_role":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"current_creator_id":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"current_session_id":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"deal_committed_set":
{ Args: { "p_deal": string,"p_paise": number }; Returns: undefined
                           },
"deal_content_facts":
{ Args: { "p_deal": string }; Returns: Json
                           },
"deal_create":
{ Args: { "p": Json }; Returns: string
                           },
"deal_delete_draft":
{ Args: { "p_deal": string }; Returns: undefined
                           },
"deal_detail":
{ Args: { "p_deal": string }; Returns: Json
                           },
"deal_from_application":
{ Args: { "p_app": string,"p_config": Json }; Returns: string
                           },
"deal_manual_event":
{ Args: { "p_deal": string,"p_kind": string,"p_reason": string,"p_ref": string }; Returns: string
                           },
"deal_model":
{ Args: { "p": Json }; Returns: string
                           },
"deal_notify":
{ Args: { "p_body": string,"p_deal": string,"p_event": string,"p_title": string,"p_to": string }; Returns: undefined
                           },
"deal_preset_archive":
{ Args: { "p_archived": boolean,"p_id": string }; Returns: undefined
                           },
"deal_preset_save":
{ Args: { "p": Json }; Returns: string
                           },
"deal_presets_list":
{ Args: { "p_include_archived"?: boolean }; Returns: Json
                           },
"deal_propose":
{ Args: { "p_deal": string,"p_effective_from"?: string,"p_note"?: string }; Returns: string
                           },
"deal_renew":
{ Args: { "p_deal": string,"p_ends_on"?: string,"p_starts_on": string }; Returns: string
                           },
"deal_set_status":
{ Args: { "p_deal": string,"p_reason"?: string,"p_status": string }; Returns: undefined
                           },
"deal_update":
{ Args: { "p": Json,"p_deal": string }; Returns: undefined
                           },
"deal_version_from_counter":
{ Args: { "p_config": Json,"p_request": string }; Returns: string
                           },
"deal_version_json":
{ Args: { "v": Omit<Database["inf"]['Tables']["deal_versions"]['Row'], Database["inf"]['Tables']["deal_versions"]['ComputedFields']> }; Returns: Json
                           },
"deal_version_respond":
{ Args: { "p_accept": boolean,"p_reason"?: string,"p_version": string }; Returns: undefined
                           },
"deal_version_withdraw":
{ Args: { "p_version": string }; Returns: undefined
                           },
"deals_expire":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"deals_list":
{ Args: { "p": Json }; Returns: Json
                           },
"deliverable_apply":
{ Args: { "p_action": string,"p_id": string,"p_note": string,"p_side": string }; Returns: string
                           },
"deliverable_detail":
{ Args: { "p_id": string }; Returns: Json
                           },
"deliverable_file_allowed":
{ Args: { "p_deliverable": string,"p_path": string }; Returns: boolean
                           },
"deliverable_next":
{ Args: { "p_action": string,"p_from": string,"s": Json }; Returns: string
                           },
"deliverable_overdue_days":
{ Args: { "p_due": Json,"p_now"?: string,"p_status": string,"s": Json }; Returns: number
                           },
"deliverable_pending":
{ Args: { "p_status": string,"s": Json }; Returns: string
                           },
"deliverable_schedule":
{ Args: { "p_at": string,"p_id": string }; Returns: undefined
                           },
"deliverable_set_status":
{ Args: { "p_action": string,"p_id": string,"p_reason"?: string }; Returns: undefined
                           },
"deliverable_update":
{ Args: { "p": Json,"p_id": string }; Returns: undefined
                           },
"deliverable_upload_allowed":
{ Args: { "p_id": string }; Returns: boolean
                           },
"deliverables_create":
{ Args: { "p_deal": string,"p_items": Json }; Returns: number
                           },
"deliverables_list":
{ Args: { "p": Json }; Returns: Json
                           },
"delivery_result":
{ Args: { "p_error"?: string,"p_id": number,"p_provider"?: string,"p_ref"?: string,"p_status": string }; Returns: undefined
                           },
"device_revoke":
{ Args: { "p_id": string }; Returns: boolean
                           },
"device_trust_check":
{ Args: { "p_token": string }; Returns: boolean
                           },
"digest_facts":
{ Args: { "p_creator"?: string,"p_days": number,"p_kind": string,"p_user": string }; Returns: Json
                           },
"digest_preference_set":
{ Args: { "p_channel": string,"p_frequency": string }; Returns: undefined
                           },
"digest_recipients":
{ Args: { "p_today": string }; Returns: {
              "channel": string,"creator_id": string,"frequency": string,"kind": string,"user_id": string
            }[]
                           },
"digest_send":
{ Args: { "p_body": string,"p_channel": string,"p_date": string,"p_kind": string,"p_title": string,"p_user": string }; Returns: string
                           },
"digests_enqueue":
{ Args: Record<PropertyKey, never>; Returns: undefined
                           },
"early_access_wait":
{ Args: { "p_creator": string }; Returns: string
                           },
"eligibility_gaps":
{ Args: { "p_campaign": string,"p_creator": string }; Returns: (string)[]
                           },
"emit_event":
{ Args: { "p_idem_key": string,"p_payload": Json,"p_subject_id": string,"p_subject_type": string,"p_type": string }; Returns: number
                           },
"finance_file_allowed":
{ Args: { "p_path": string }; Returns: boolean
                           },
"follow_up_done":
{ Args: { "p_activity": string }; Returns: undefined
                           },
"follow_ups_due":
{ Args: { "p_limit"?: number,"p_scope"?: string }; Returns: {
              "activity_id": string,"creator_id": string,"display_name": string,"handle": string,"next_follow_up_at": string,"notes": string,"outcome": string,"overdue": boolean,"owner_name": string
            }[]
                           },
"fraud_apply":
{ Args: { "p": Json }; Returns: number
                           },
"fraud_decide":
{ Args: { "p_confirm": boolean,"p_flag": string,"p_note": string }; Returns: undefined
                           },
"fraud_facts":
{ Args: { "p_creators": (string)[] }; Returns: Json
                           },
"fraud_queue":
{ Args: { "p": Json }; Returns: Json
                           },
"fy_of":
{ Args: { "p": string }; Returns: string
                           },
"fy_quarter_of":
{ Args: { "p": string }; Returns: string
                           },
"has_perm":
{ Args: { "p_permission": string }; Returns: boolean
                           },
"health":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"idle_limit":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"inr":
{ Args: { "p_paise": number }; Returns: string
                           },
"invite_decline":
{ Args: { "p_invite": string,"p_reason": string }; Returns: undefined
                           },
"invite_withdraw":
{ Args: { "p_invite": string }; Returns: undefined
                           },
"invoice_review":
{ Args: { "p_accept": boolean,"p_invoice": string,"p_note": string }; Returns: undefined
                           },
"invoice_submit":
{ Args: { "p": Json }; Returns: string
                           },
"invoice_upload_allowed":
{ Args: { "p_payout": string }; Returns: boolean
                           },
"invoices_queue":
{ Args: { "p_status": string }; Returns: Json
                           },
"is_staff":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"ist_date":
{ Args: { "p": string }; Returns: string
                           },
"job_claim":
{ Args: { "p_kinds"?: (string)[],"p_limit"?: number,"p_worker": string }; Returns: {
              "attempts": number,
"created_at": string,
"finished_at": string | null,
"id": number,
"idem_key": string | null,
"kind": string,
"last_error": string | null,
"locked_at": string | null,
"locked_by": string | null,
"max_attempts": number,
"payload": NonNullable<Json>,
"run_at": string,
"status": string
            }[]
                          SetofOptions: {
        from: "*"
        to: "jobs"
        isOneToOne: false
        isSetofReturn: true
      } },
"job_enqueue":
{ Args: { "p_idem_key"?: string,"p_kind": string,"p_max_attempts"?: number,"p_payload": Json,"p_run_at"?: string }; Returns: number
                           },
"job_finish":
{ Args: { "p_error"?: string,"p_id": number,"p_ok": boolean }; Returns: string
                           },
"job_retry":
{ Args: { "p_id": number }; Returns: boolean
                           },
"jobs_recent":
{ Args: { "p_limit"?: number,"p_status"?: string }; Returns: {
              "attempts": number,"created_at": string,"finished_at": string,"id": number,"kind": string,"last_error": string,"max_attempts": number,"run_at": string,"status": string
            }[]
                           },
"json_matches_schema":
{ Args: { "p_schema": Json,"p_value": Json }; Returns: boolean
                           },
"json_schema_errors":
{ Args: { "p_path"?: string,"p_schema": Json,"p_value": Json }; Returns: (string)[]
                           },
"kyc_queue":
{ Args: Record<PropertyKey, never>; Returns: {
              "creator_id": string,"display_name": string,"gst_status": string,"handle": string,"status": string,"submitted_at": string
            }[]
                           },
"kyc_reveal":
{ Args: { "p_creator": string,"p_reason": string }; Returns: Json
                           },
"kyc_save":
{ Args: { "p_account_holder": string,"p_bank_account": string,"p_creator": string,"p_gst_status": string,"p_gstin": string,"p_ifsc": string,"p_name_on_pan": string,"p_pan": string,"p_proof_path"?: string }; Returns: Json
                           },
"kyc_verify":
{ Args: { "p_approve": boolean,"p_creator": string,"p_gstin_verified"?: boolean,"p_reason": string }; Returns: undefined
                           },
"kyc_view":
{ Args: { "p_creator": string }; Returns: Json
                           },
"lead_backfill":
{ Args: { "p_from": string,"p_to": string }; Returns: number
                           },
"lead_detail":
{ Args: { "p_attribution": string }; Returns: Json
                           },
"lead_feed_earnings":
{ Args: { "p_deal": string }; Returns: undefined
                           },
"lead_feed_refresh":
{ Args: { "p_lead": number }; Returns: undefined
                           },
"lead_ref":
{ Args: { "p_lead": number }; Returns: string
                           },
"lead_sync_apply":
{ Args: { "p": Json }; Returns: Json
                           },
"lead_sync_candidates":
{ Args: { "p": Json }; Returns: Json
                           },
"lead_sync_since":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"lead_view_delete":
{ Args: { "p_id": string }; Returns: undefined
                           },
"lead_view_save":
{ Args: { "p_filters": Json,"p_name": string,"p_shared": boolean }; Returns: string
                           },
"lead_views":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"leads_list":
{ Args: { "p": Json }; Returns: Json
                           },
"ledger_adjust":
{ Args: { "p": Json }; Returns: number
                           },
"ledger_apply":
{ Args: { "p": Json,"p_deal": string }; Returns: Json
                           },
"ledger_can_transition":
{ Args: { "p_from": string,"p_to": string }; Returns: boolean
                           },
"ledger_deals_to_run":
{ Args: Record<PropertyKey, never>; Returns: string[]
                           },
"ledger_enqueue":
{ Args: { "p_deal": string,"p_reason": string }; Returns: undefined
                           },
"ledger_entry_events":
{ Args: { "p_entry": number }; Returns: Json
                           },
"ledger_facts":
{ Args: { "p_deal": string }; Returns: Json
                           },
"ledger_hold":
{ Args: { "p_entry": number,"p_hold": boolean,"p_reason": string }; Returns: string
                           },
"ledger_hold_creator":
{ Args: { "p_creator": string,"p_hold": boolean,"p_reason": string }; Returns: number
                           },
"ledger_in_open_batch":
{ Args: { "p_entry": number }; Returns: boolean
                           },
"ledger_list":
{ Args: { "p": Json }; Returns: Json
                           },
"ledger_nightly":
{ Args: Record<PropertyKey, never>; Returns: undefined
                           },
"ledger_post":
{ Args: { "p": Json }; Returns: number
                           },
"ledger_refresh_due":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"ledger_status_of":
{ Args: { "p_amount": number,"p_confirmed": number,"p_due_on": string,"p_held": boolean,"p_in_open_batch": boolean,"p_is_reversal": boolean,"p_paid": number,"p_reversed": boolean,"p_today": string }; Returns: string
                           },
"ledger_transition":
{ Args: { "p_entry": number,"p_reason"?: string }; Returns: string
                           },
"ledger_writer_on":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"ledger_writer_restore":
{ Args: { "p_prev": string }; Returns: undefined
                           },
"link_code_suggest":
{ Args: { "p_handle": string,"p_tag": string }; Returns: string
                           },
"link_create":
{ Args: { "p": Json }; Returns: string
                           },
"link_options":
{ Args: { "p_creator": string }; Returns: Json
                           },
"link_resolve":
{ Args: { "p_code": string }; Returns: Json
                           },
"link_set_active":
{ Args: { "p_active": boolean,"p_link": string }; Returns: undefined
                           },
"links_list":
{ Args: { "p_creator": string }; Returns: Json
                           },
"marketplace":
{ Args: { "p_all"?: boolean,"p_creator"?: string }; Returns: Json
                           },
"mask_email":
{ Args: { "p": string,"p_public": (string)[] }; Returns: string
                           },
"mask_phone":
{ Args: { "p": string }; Returns: string
                           },
"me":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"media_kit":
{ Args: { "p_creator": string }; Returns: Json
                           },
"media_kit_data":
{ Args: { "p_creator": string,"p_rates": boolean }; Returns: Json
                           },
"media_kit_public":
{ Args: { "p_handle": string }; Returns: Json
                           },
"media_kit_settings":
{ Args: { "p_creator": string,"p_public": boolean,"p_show_rates": boolean }; Returns: undefined
                           },
"mentionable_staff":
{ Args: Record<PropertyKey, never>; Returns: {
              "full_name": string,"user_id": string
            }[]
                           },
"metrics_submit":
{ Args: { "p": Json,"p_deliverable": string }; Returns: number
                           },
"mfa_issue":
{ Args: { "p_session": string,"p_user": string }; Returns: Json
                           },
"mfa_verify":
{ Args: { "p_code": string,"p_label"?: string,"p_trust"?: boolean }; Returns: Json
                           },
"my_agency_links":
{ Args: Record<PropertyKey, never>; Returns: {
              "agency_name": string,"can_act_deliverables": boolean,"can_negotiate_sign": boolean,"can_view": boolean,"can_view_earnings": boolean,"link_id": string,"requested_at": string,"responded_at": string,"status": string
            }[]
                           },
"my_announcements":
{ Args: { "p_limit"?: number }; Returns: Json
                           },
"my_applications":
{ Args: { "p_creator"?: string }; Returns: {
              "campaign_id": string,"campaign_name": string,"created_at": string,"id": string,"open_offer_from": string,"source": string,"status": string,"updated_at": string
            }[]
                           },
"my_briefs":
{ Args: { "p_creator": string }; Returns: Json
                           },
"my_consents":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"my_contracts":
{ Args: { "p_creator": string }; Returns: Json
                           },
"my_deals":
{ Args: { "p_creator": string }; Returns: Json
                           },
"my_deliverables":
{ Args: { "p_creator": string }; Returns: Json
                           },
"my_devices":
{ Args: Record<PropertyKey, never>; Returns: {
              "created_at": string,"expires_at": string,"id": string,"label": string,"last_used_at": string
            }[]
                           },
"my_invites":
{ Args: { "p_creator"?: string }; Returns: {
              "apply_by": string,"campaign_id": string,"campaign_name": string,"compensation_summary": string,"id": string,"message": string,"sent_at": string,"status": string
            }[]
                           },
"my_notification_preferences":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"my_notifications":
{ Args: { "p_before"?: string,"p_limit"?: number }; Returns: {
              "body": string,"created_at": string,"data": Json,"event": string,"id": string,"link": string,"read_at": string,"title": string
            }[]
                           },
"my_notifications_page":
{ Args: { "p_before"?: string,"p_limit"?: number,"p_unread"?: boolean }; Returns: Json
                           },
"my_privacy_requests":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"my_sessions":
{ Args: Record<PropertyKey, never>; Returns: {
              "created_at": string,"ip": unknown,"is_current": boolean,"kind": string,"last_seen_at": string,"revoked_at": string,"session_id": string,"user_agent": string,"verified": boolean
            }[]
                           },
"my_threads":
{ Args: { "p"?: Json }; Returns: Json
                           },
"my_unread_counts":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"nightly_prune":
{ Args: Record<PropertyKey, never>; Returns: undefined
                           },
"norm_phone":
{ Args: { "p": string }; Returns: string
                           },
"notification_preference_set":
{ Args: { "p_channel": string,"p_enabled": boolean,"p_event": string }; Returns: undefined
                           },
"notification_template_for":
{ Args: { "p_channel": string,"p_event": string }; Returns: Json
                           },
"notification_template_reset":
{ Args: { "p_channel": string,"p_event": string }; Returns: undefined
                           },
"notification_template_save":
{ Args: { "p": Json }; Returns: string
                           },
"notification_template_vars_ok":
{ Args: { "p_event": string,"p_text": string }; Returns: boolean
                           },
"notification_templates_list":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"notifications_mark_all_read":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"notifications_mark_read":
{ Args: { "p_ids": (string)[] }; Returns: number
                           },
"notify":
{ Args: { "p_body": string,"p_channels"?: (string)[],"p_data": Json,"p_event": string,"p_idem_key": string,"p_link": string,"p_mandatory": boolean,"p_title": string,"p_user": string }; Returns: string
                           },
"offer_accept":
{ Args: { "p_offer": string }; Returns: undefined
                           },
"offer_make":
{ Args: { "p_app": string,"p_message": string,"p_terms": Json }; Returns: string
                           },
"onboarding_state":
{ Args: { "p_creator"?: string }; Returns: Json
                           },
"onboarding_submit":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"outreach_log":
{ Args: { "p_channel": string,"p_creator": string,"p_direction": string,"p_next_follow_up"?: string,"p_notes": string,"p_outcome": string }; Returns: string
                           },
"payout_advice_saved":
{ Args: { "p_path": string,"p_payout": string }; Returns: undefined
                           },
"payout_bank_rows":
{ Args: { "p_batch": string }; Returns: Json
                           },
"payout_batch_approve":
{ Args: { "p_batch": string }; Returns: string
                           },
"payout_batch_cancel":
{ Args: { "p_batch": string,"p_reason": string }; Returns: undefined
                           },
"payout_batch_create":
{ Args: { "p": Json }; Returns: string
                           },
"payout_batch_detail":
{ Args: { "p_batch": string }; Returns: Json
                           },
"payout_batches_list":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"payout_candidates":
{ Args: { "p": Json }; Returns: Json
                           },
"payout_detail":
{ Args: { "p_payout": string }; Returns: Json
                           },
"payout_mark_failed":
{ Args: { "p_payout": string,"p_reason": string }; Returns: undefined
                           },
"payout_release_items":
{ Args: { "p_payout": string,"p_reason": string }; Returns: undefined
                           },
"payout_remove":
{ Args: { "p_payout": string,"p_reason": string }; Returns: undefined
                           },
"payouts_mark_paid":
{ Args: { "p": Json }; Returns: number
                           },
"penalties_list":
{ Args: { "p": Json }; Returns: Json
                           },
"penalty_decide":
{ Args: { "p_approve": boolean,"p_id": string,"p_note"?: string }; Returns: undefined
                           },
"penalty_proposals_sync":
{ Args: { "p_deal": string,"p_items": Json }; Returns: number
                           },
"pii_decrypt":
{ Args: { "p": string }; Returns: string
                           },
"pii_encrypt":
{ Args: { "p": string }; Returns: string
                           },
"pii_hash":
{ Args: { "p": string }; Returns: string
                           },
"pii_key":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"platform_delete":
{ Args: { "p_creator": string,"p_id": string }; Returns: undefined
                           },
"platform_save":
{ Args: { "p": Json,"p_creator": string }; Returns: string
                           },
"portfolio_delete":
{ Args: { "p_creator": string,"p_id": string }; Returns: undefined
                           },
"portfolio_save":
{ Args: { "p": Json,"p_creator": string }; Returns: string
                           },
"post_submit":
{ Args: { "p_deliverable": string,"p_oembed"?: Json,"p_posted_on": string,"p_url": string }; Returns: string
                           },
"post_verify":
{ Args: { "p_disclosure": boolean,"p_live": boolean,"p_matches": boolean,"p_note"?: string,"p_post": string }; Returns: undefined
                           },
"privacy_deletion_decide":
{ Args: { "p_approve": boolean,"p_note": string,"p_purge_on"?: string,"p_request": string }; Returns: string
                           },
"privacy_deletion_facts":
{ Args: { "p_request": string }; Returns: Json
                           },
"privacy_export_allowed":
{ Args: { "p_request": string }; Returns: boolean
                           },
"privacy_export_data":
{ Args: { "p_request": string }; Returns: Json
                           },
"privacy_request_create":
{ Args: { "p_kind": string,"p_reason"?: string }; Returns: string
                           },
"privacy_requests_list":
{ Args: { "p_status"?: string }; Returns: Json
                           },
"programme_scorecards":
{ Args: { "p_period": string }; Returns: Json
                           },
"public_creator":
{ Args: { "p_handle": string }; Returns: Json
                           },
"rate_card_delete":
{ Args: { "p_creator": string,"p_id": string }; Returns: undefined
                           },
"rate_card_save":
{ Args: { "p": Json,"p_creator": string }; Returns: string
                           },
"rate_check":
{ Args: { "p_key": string,"p_limit": number,"p_seconds": number }; Returns: boolean
                           },
"receipt_record":
{ Args: { "p": Json }; Returns: number
                           },
"receipts_effective":
{ Args: Record<PropertyKey, never>; Returns: {
              "created_at": string,
"enrollment_ref": string,
"enrollment_status": string | null,
"entered_by": string | null,
"gross_paise": number,
"gst_paise": number,
"id": number,
"net_paise": number,
"reason": string | null,
"received_on": string | null,
"received_paise": number,
"source": string,
"source_version": string,
"status": string,
"student_lead_id": number
            }[]
                          SetofOptions: {
        from: "*"
        to: "eduwit_commission_receipts"
        isOneToOne: false
        isSetofReturn: true
      } },
"recon_data":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"request_header":
{ Args: { "p_name": string }; Returns: string
                           },
"request_id":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"request_ip":
{ Args: Record<PropertyKey, never>; Returns: unknown
                           },
"request_user_agent":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"retention_run":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"review_comment_add":
{ Args: { "p_body": string,"p_parent"?: string,"p_region"?: Json,"p_submission": string,"p_timestamp_ms"?: number }; Returns: string
                           },
"review_comment_set_resolved":
{ Args: { "p_comment": string,"p_resolved": boolean }; Returns: undefined
                           },
"revision_extension_decide":
{ Args: { "p_approve": boolean,"p_id": string,"p_note"?: string }; Returns: undefined
                           },
"revision_extension_request":
{ Args: { "p_deliverable": string,"p_fee_paise"?: number,"p_reason": string }; Returns: string
                           },
"saved_view_delete":
{ Args: { "p_id": string }; Returns: undefined
                           },
"saved_view_save":
{ Args: { "p_filters": Json,"p_name": string,"p_shared": boolean }; Returns: string
                           },
"scorecard_facts":
{ Args: { "p_creator": string,"p_from": string,"p_to": string }; Returns: Json
                           },
"scorecard_periods":
{ Args: Record<PropertyKey, never>; Returns: string[]
                           },
"scorecard_save":
{ Args: { "p": Json }; Returns: string
                           },
"scorecards_due":
{ Args: { "p_period": string }; Returns: string[]
                           },
"session_ok":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"session_register":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"session_revoke":
{ Args: { "p_session_id": string }; Returns: boolean
                           },
"session_touch":
{ Args: Record<PropertyKey, never>; Returns: undefined
                           },
"setting":
{ Args: { "p_key": string }; Returns: Json
                           },
"setting_confirm":
{ Args: { "p_key": string,"p_note": string }; Returns: undefined
                           },
"setting_history":
{ Args: { "p_key": string }; Returns: {
              "actor_name": string,"at": string,"reason": string,"value": Json,"version": number
            }[]
                           },
"setting_set":
{ Args: { "p_expected_version": number,"p_key": string,"p_reason": string,"p_value": Json }; Returns: Json
                           },
"settings_list":
{ Args: Record<PropertyKey, never>; Returns: {
              "can_edit": boolean,"confirmed_at": string,"default_value": Json,"description": string,"grp": string,"is_default": boolean,"json_schema": Json,"key": string,"label": string,"needs_confirmation": string,"updated_at": string,"updated_by_name": string,"value": Json,"version": number
            }[]
                           },
"sign_in_locked":
{ Args: { "p_email": string }; Returns: boolean
                           },
"sign_in_record":
{ Args: { "p_email": string,"p_ip"?: string,"p_method": string,"p_outcome": string,"p_portal": string,"p_reason"?: string,"p_ua"?: string,"p_user"?: string }; Returns: undefined
                           },
"staff_list":
{ Args: Record<PropertyKey, never>; Returns: {
              "created_at": string,"email": string,"full_name": string,"is_signatory": boolean,"last_seen_at": string,"roles": (string)[],"signatory_designation": string,"status": string,"user_id": string
            }[]
                           },
"staff_revoke_all_sessions":
{ Args: { "p_reason": string,"p_user": string }; Returns: number
                           },
"staff_save":
{ Args: { "p_designation"?: string,"p_email": string,"p_full_name": string,"p_is_signatory": boolean,"p_roles": (string)[],"p_user": string }; Returns: undefined
                           },
"staff_set_status":
{ Args: { "p_reason": string,"p_status": string,"p_user": string }; Returns: undefined
                           },
"stage_mapping_save":
{ Args: { "p": Json }; Returns: string
                           },
"status_for_stage":
{ Args: { "p_stage": string,"p_status": string }; Returns: string
                           },
"submission_add":
{ Args: { "p": Json,"p_deliverable": string }; Returns: string
                           },
"submission_review":
{ Args: { "p_checklist"?: Json,"p_decision": string,"p_note": string,"p_submission": string }; Returns: undefined
                           },
"system_status":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"task_save":
{ Args: { "p": Json }; Returns: string
                           },
"task_set_status":
{ Args: { "p_status": string,"p_task": string }; Returns: undefined
                           },
"tds_certificate_record":
{ Args: { "p_creator": string,"p_fy": string,"p_path": string,"p_quarter": string }; Returns: string
                           },
"tds_section_save":
{ Args: { "p": Json }; Returns: undefined
                           },
"tds_sections_list":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"tds_summary":
{ Args: { "p_fy": string,"p_quarter": string }; Returns: Json
                           },
"template_archive":
{ Args: { "p_archived": boolean,"p_template": string }; Returns: undefined
                           },
"template_save":
{ Args: { "p": Json }; Returns: string
                           },
"template_source":
{ Args: { "p_template": string }; Returns: Json
                           },
"terms_accept":
{ Args: { "p_terms_version_id": string }; Returns: undefined
                           },
"terms_pending":
{ Args: Record<PropertyKey, never>; Returns: {
              "body": string,"effective_at": string,"id": string,"kind": string,"title": string,"version": number
            }[]
                           },
"terms_publish":
{ Args: { "p_body": string,"p_kind": string,"p_title": string }; Returns: string
                           },
"thread_file_allowed":
{ Args: { "p_path": string }; Returns: boolean
                           },
"thread_get":
{ Args: { "p_creator"?: string,"p_entity": string,"p_type": string }; Returns: Json
                           },
"thread_mark_read":
{ Args: { "p_thread": string }; Returns: undefined
                           },
"thread_open":
{ Args: { "p_creator"?: string,"p_entity": string,"p_type": string }; Returns: string
                           },
"thread_post":
{ Args: { "p_attachments"?: Json,"p_body": string,"p_creator"?: string,"p_entity": string,"p_type": string }; Returns: Json
                           },
"thread_resolve":
{ Args: { "p_creator"?: string,"p_entity": string,"p_type": string }; Returns: Json
                           },
"thread_staff_followers":
{ Args: { "p_owner": string,"p_thread": string }; Returns: string[]
                           },
"tier_clear_manual":
{ Args: { "p_creator": string }; Returns: undefined
                           },
"tier_json_ok":
{ Args: { "p_benefits": Json,"p_rules": Json }; Returns: boolean
                           },
"tier_save":
{ Args: { "p": Json }; Returns: string
                           },
"tier_set_manual":
{ Args: { "p_creator": string,"p_reason": string,"p_tier"?: string,"p_until": string }; Returns: undefined
                           },
"tier_status":
{ Args: { "p_creator": string }; Returns: Json
                           },
"tiers_list":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"valid_gstin":
{ Args: { "p": string }; Returns: boolean
                           },
"valid_ifsc":
{ Args: { "p": string }; Returns: boolean
                           },
"valid_pan":
{ Args: { "p": string }; Returns: boolean
                           },
"webhook_delivery_get":
{ Args: { "p_id": number }; Returns: Json
                           },
"webhook_delivery_result":
{ Args: { "p_error"?: string,"p_id": number,"p_next_at"?: string,"p_outcome": string,"p_status"?: number }; Returns: undefined
                           },
"webhook_endpoint_create":
{ Args: { "p": Json }; Returns: string
                           },
"webhook_endpoint_delete":
{ Args: { "p_id": string }; Returns: undefined
                           },
"webhook_endpoint_update":
{ Args: { "p": Json,"p_id": string }; Returns: undefined
                           },
"webhook_enqueue":
{ Args: { "p_endpoint": string,"p_event": string,"p_event_id": string,"p_payload": Json }; Returns: undefined
                           },
"webhook_host_ok":
{ Args: { "p_url": string }; Returns: boolean
                           },
"webhook_test":
{ Args: { "p_id": string }; Returns: undefined
                           },
"webhooks_list":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"witty_issue_code":
{ Args: { "p": Json }; Returns: Json
                           },
"witty_resolve_code":
{ Args: { "p_code": string }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "inf": {
          Enums: {
            
          }
        }
} as const
