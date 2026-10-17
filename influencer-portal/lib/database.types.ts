
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
                    "apply_by": string | null,"budget_paise": number | null,"compensation_summary": string | null,"contract_template_id": string | null,"created_at": string,"created_by": string,"default_preset_id": string | null,"deliverables": NonNullable<Json>,"description": string | null,"eligibility": NonNullable<Json>,"ends_on": string | null,"id": string,"internal_notes": string | null,"name": string,"objective": string,"owner_id": string | null,"slots": number | null,"starts_on": string | null,"status": string,"updated_at": string,"visibility": string
                  }
                  ComputedFields: never
                  Insert: {
                    "apply_by"?: string | null,"budget_paise"?: number | null,"compensation_summary"?: string | null,"contract_template_id"?: string | null,"created_at"?: string,"created_by"?: string,"default_preset_id"?: string | null,"deliverables"?: NonNullable<Json>,"description"?: string | null,"eligibility"?: NonNullable<Json>,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"name": string,"objective": string,"owner_id"?: string | null,"slots"?: number | null,"starts_on"?: string | null,"status"?: string,"updated_at"?: string,"visibility"?: string
                  }
                  Update: {
                    "apply_by"?: string | null,"budget_paise"?: number | null,"compensation_summary"?: string | null,"contract_template_id"?: string | null,"created_at"?: string,"created_by"?: string,"default_preset_id"?: string | null,"deliverables"?: NonNullable<Json>,"description"?: string | null,"eligibility"?: NonNullable<Json>,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"name"?: string,"objective"?: string,"owner_id"?: string | null,"slots"?: number | null,"starts_on"?: string | null,"status"?: string,"updated_at"?: string,"visibility"?: string
                  }
                  Relationships: [
                    {
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
                    "activated_at": string | null,"agreed_at": string | null,"agreed_terms": Json | null,"application_id": string | null,"campaign_id": string | null,"closed_at": string | null,"code": string,"created_at": string,"created_by": string | null,"creator_id": string,"current_version_id": string | null,"deal_model": string,"draft_config": Json | null,"ends_on": string | null,"id": string,"internal_notes": string | null,"owner_id": string | null,"preset_id": string | null,"starts_on": string,"status": string,"status_reason": string | null,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "activated_at"?: string | null,"agreed_at"?: string | null,"agreed_terms"?: Json | null,"application_id"?: string | null,"campaign_id"?: string | null,"closed_at"?: string | null,"code"?: string,"created_at"?: string,"created_by"?: string | null,"creator_id": string,"current_version_id"?: string | null,"deal_model"?: string,"draft_config"?: Json | null,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"owner_id"?: string | null,"preset_id"?: string | null,"starts_on": string,"status"?: string,"status_reason"?: string | null,"title": string,"updated_at"?: string
                  }
                  Update: {
                    "activated_at"?: string | null,"agreed_at"?: string | null,"agreed_terms"?: Json | null,"application_id"?: string | null,"campaign_id"?: string | null,"closed_at"?: string | null,"code"?: string,"created_at"?: string,"created_by"?: string | null,"creator_id"?: string,"current_version_id"?: string | null,"deal_model"?: string,"draft_config"?: Json | null,"ends_on"?: string | null,"id"?: string,"internal_notes"?: string | null,"owner_id"?: string | null,"preset_id"?: string | null,"starts_on"?: string,"status"?: string,"status_reason"?: string | null,"title"?: string,"updated_at"?: string
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
    }
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
                },"messages": {
                  Row: {
                    "author_id": string,"author_side": string,"body": string,"created_at": string,"id": string,"thread_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id"?: string,"author_side": string,"body": string,"created_at"?: string,"id"?: string,"thread_id": string
                  }
                  Update: {
                    "author_id"?: string,"author_side"?: string,"body"?: string,"created_at"?: string,"id"?: string,"thread_id"?: string
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
                },"threads": {
                  Row: {
                    "created_at": string,"entity_id": string,"entity_type": string,"id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"entity_id": string,"entity_type": string,"id"?: string
                  }
                  Update: {
                    "created_at"?: string,"entity_id"?: string,"entity_type"?: string,"id"?: string
                  }
                  Relationships: [
                    
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
                }
          }
          Views: {
            [_ in never]: never
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
"audit":
{ Args: { "p_action": string,"p_after"?: Json,"p_before"?: Json,"p_entity_id": string,"p_entity_type": string }; Returns: undefined
                           },
"auth_user_id_by_email":
{ Args: { "p_email": string }; Returns: string
                           },
"avatar_set":
{ Args: { "p_creator": string,"p_path"?: string }; Returns: undefined
                           },
"bootstrap_super_admin":
{ Args: { "p_designation": string,"p_email": string,"p_full_name": string }; Returns: string
                           },
"campaign_apply":
{ Args: { "p_campaign": string,"p_creator": string,"p_pitch": string,"p_samples": (string)[],"p_terms": Json }; Returns: string
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
"code_hash":
{ Args: { "p_code": string,"p_salt": string,"p_user": string }; Returns: string
                           },
"commission_estimate":
{ Args: { "p_campaign": string }; Returns: number
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
"config_hash":
{ Args: { "p": Json }; Returns: string
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
"creator_delete_draft":
{ Args: { "p_creator": string }; Returns: undefined
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
{ Args: { "p_deal": string,"p_ends_on": string,"p_starts_on": string }; Returns: string
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
"delivery_result":
{ Args: { "p_error"?: string,"p_id": number,"p_provider"?: string,"p_ref"?: string,"p_status": string }; Returns: undefined
                           },
"device_revoke":
{ Args: { "p_id": string }; Returns: boolean
                           },
"device_trust_check":
{ Args: { "p_token": string }; Returns: boolean
                           },
"eligibility_gaps":
{ Args: { "p_campaign": string,"p_creator": string }; Returns: (string)[]
                           },
"emit_event":
{ Args: { "p_idem_key": string,"p_payload": Json,"p_subject_id": string,"p_subject_type": string,"p_type": string }; Returns: number
                           },
"follow_up_done":
{ Args: { "p_activity": string }; Returns: undefined
                           },
"follow_ups_due":
{ Args: { "p_limit"?: number,"p_scope"?: string }; Returns: {
              "activity_id": string,"creator_id": string,"display_name": string,"handle": string,"next_follow_up_at": string,"notes": string,"outcome": string,"overdue": boolean,"owner_name": string
            }[]
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
"invite_decline":
{ Args: { "p_invite": string,"p_reason": string }; Returns: undefined
                           },
"invite_withdraw":
{ Args: { "p_invite": string }; Returns: undefined
                           },
"is_staff":
{ Args: Record<PropertyKey, never>; Returns: boolean
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
"marketplace":
{ Args: { "p_all"?: boolean,"p_creator"?: string }; Returns: Json
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
"my_applications":
{ Args: { "p_creator"?: string }; Returns: {
              "campaign_id": string,"campaign_name": string,"created_at": string,"id": string,"open_offer_from": string,"source": string,"status": string,"updated_at": string
            }[]
                           },
"my_contracts":
{ Args: { "p_creator": string }; Returns: Json
                           },
"my_deals":
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
"my_notifications":
{ Args: { "p_before"?: string,"p_limit"?: number }; Returns: {
              "body": string,"created_at": string,"data": Json,"event": string,"id": string,"link": string,"read_at": string,"title": string
            }[]
                           },
"my_sessions":
{ Args: Record<PropertyKey, never>; Returns: {
              "created_at": string,"ip": unknown,"is_current": boolean,"kind": string,"last_seen_at": string,"revoked_at": string,"session_id": string,"user_agent": string,"verified": boolean
            }[]
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
"rate_card_delete":
{ Args: { "p_creator": string,"p_id": string }; Returns: undefined
                           },
"rate_card_save":
{ Args: { "p": Json,"p_creator": string }; Returns: string
                           },
"rate_check":
{ Args: { "p_key": string,"p_limit": number,"p_seconds": number }; Returns: boolean
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
"saved_view_delete":
{ Args: { "p_id": string }; Returns: undefined
                           },
"saved_view_save":
{ Args: { "p_filters": Json,"p_name": string,"p_shared": boolean }; Returns: string
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
"status_for_stage":
{ Args: { "p_stage": string,"p_status": string }; Returns: string
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
"tds_section_save":
{ Args: { "p": Json }; Returns: undefined
                           },
"tds_sections_list":
{ Args: Record<PropertyKey, never>; Returns: Json
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
"valid_gstin":
{ Args: { "p": string }; Returns: boolean
                           },
"valid_ifsc":
{ Args: { "p": string }; Returns: boolean
                           },
"valid_pan":
{ Args: { "p": string }; Returns: boolean
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
