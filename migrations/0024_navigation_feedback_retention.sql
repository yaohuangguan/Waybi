-- Bounded daily retention for anonymous navigation feedback votes.
CREATE INDEX IF NOT EXISTS idx_navigation_feedback_created_at ON navigation_feedback (created_at);
