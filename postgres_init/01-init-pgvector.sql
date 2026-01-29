-- Install pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create chat history vector store table
CREATE TABLE IF NOT EXISTS chat_history_vectors (
    id SERIAL PRIMARY KEY,
    content TEXT,
    metadata JSONB,
    embedding vector(1536),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create global knowledge base vector store table
CREATE TABLE IF NOT EXISTS knowledge_base_vectors (
    id SERIAL PRIMARY KEY,
    content TEXT,
    metadata JSONB,
    embedding vector(1536),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for similarity search
CREATE INDEX IF NOT EXISTS chat_history_embedding_idx 
ON chat_history_vectors USING ivfflat (embedding vector_cosine_ops);

CREATE INDEX IF NOT EXISTS knowledge_base_embedding_idx 
ON knowledge_base_vectors USING ivfflat (embedding vector_cosine_ops);

-- Create indexes on timestamps for efficient querying
CREATE INDEX IF NOT EXISTS chat_history_created_at_idx 
ON chat_history_vectors (created_at DESC);

CREATE INDEX IF NOT EXISTS knowledge_base_updated_at_idx 
ON knowledge_base_vectors (updated_at DESC);
