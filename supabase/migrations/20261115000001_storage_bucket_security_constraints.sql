-- Migration: 20261115000001_storage_bucket_security_constraints.sql
-- Description: Enforce 25MB file size limit and strict MIME whitelist on the 'documents' storage bucket.
-- Includes 'application/octet-stream' transitionally to ensure backward compatibility with historical uploads.

UPDATE storage.buckets
SET 
  file_size_limit = 26214400, -- 25 MB in bytes
  allowed_mime_types = ARRAY[
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/plain',
    'application/rtf',
    'application/octet-stream' -- Transitional inclusion for backward compatibility
  ]
WHERE id = 'documents';
