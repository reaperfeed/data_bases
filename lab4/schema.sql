CREATE TYPE account_status AS ENUM (
    'active',
    'blocked',
    'deleted'
);
CREATE TYPE device_type AS ENUM (
    'phone_tablet',
    'computer_laptop'
);
CREATE TYPE platform_type AS ENUM (
    'ios',
    'android',
    'windows',
    'linux'
);
CREATE TYPE device_status AS ENUM (
    'connected',
    'disconnected'
);
CREATE TYPE session_status AS ENUM (
    'active',
    'inactive'
);
CREATE TYPE chat_type AS ENUM (
    'dialog',
    'group',
    'channel'
);
CREATE TYPE chat_status AS ENUM (
    'active',
    'archived',
    'deleted'
);
CREATE TYPE member_role AS ENUM (
    'member',
    'admin',
    'owner',
    'reader'
);
CREATE TYPE membership_status AS ENUM (
    'active',
    'inactive'
);
CREATE TYPE message_status AS ENUM (
    'sent',
    'edited',
    'deleted'
);
CREATE TYPE content_type AS ENUM (
    'text',
    'attachment'
);
CREATE TYPE version_type AS ENUM (
    'original',
    'edited'
);
CREATE TYPE attachment_type AS ENUM (
    'photo',
    'video',
    'audio',
    'file'
);
CREATE TYPE attachment_status AS ENUM (
    'uploading',
    'uploaded',
    'deleted'
);
CREATE TYPE representation_status AS ENUM (
    'ready',
    'not_ready'
);
CREATE TYPE delivery_event_type AS ENUM (
    'sent',
    'received_by_server',
    'delivered',
    'read'
);
CREATE TYPE complaint_status AS ENUM (
    'filed',
    'reviewed'
);
CREATE TYPE complaint_result AS ENUM (
    'satisfied',
    'rejected'
);
CREATE TYPE decision_type AS ENUM (
    'reject_complaint', 
    'restrict_message',
    'temporarily_restrict_user',
    'forward_to_senior_moderator'
);
CREATE TYPE decision_status AS ENUM (
    'executed',
    'in_queue'
);
CREATE TYPE admin_action_type AS ENUM (
    'block',
    'restrict',
    'change_access',
    'edit_message',
    'delete_message'
);
CREATE TYPE audit_result AS ENUM (
    'success',
    'error'
);
CREATE TYPE object_type AS ENUM (
    'user',
    'message',
    'attachment',
    'chat',
    'admin_action'
);

--E16
CREATE TABLE objects (
    object_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    o_type object_type NOT NULL
);


--E1
CREATE TABLE users (
    user_id uuid REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE PRIMARY KEY,
    u_login text NOT NULL UNIQUE,
    first_name text NOT NULL,
    last_name text NOT NULL,
    phone_number text CHECK (phone_number IS NULL OR phone_number ~* '^\+?[1-9]\d{1,14}$'),
    email text CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    registration_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    a_status account_status NOT NULL DEFAULT 'active',
    last_activity_date TIMESTAMPTZ NOT NULL DEFAULT now()
);

--E2
CREATE TABLE devices (
    device_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    d_type device_type NOT NULL,
    p_type platform_type NOT NULL,
    os_version text NOT NULL,
    registration_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    d_status device_status NOT NULL DEFAULT 'connected',
    last_activity_date TIMESTAMPTZ NOT NULL DEFAULT now()
);

--E3
CREATE TABLE sessions (
    session_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE ON UPDATE CASCADE,
    s_status session_status NOT NULL DEFAULT 'active',
    start_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    end_time TIMESTAMPTZ,
    CONSTRAINT chk_end_time CHECK (end_time IS NULL OR end_time > start_time)
);

--E4
CREATE TABLE chats (
    chat_id uuid REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE PRIMARY KEY,
    c_type chat_type NOT NULL,
    chat_name text,
    creation_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    c_status chat_status NOT NULL DEFAULT 'active'
);

--E5
CREATE TABLE chat_memberships (
    membership_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    chat_id uuid NOT NULL REFERENCES chats(chat_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    m_role member_role NOT NULL DEFAULT 'member',
    m_status membership_status NOT NULL DEFAULT 'active',
    join_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    leave_date TIMESTAMPTZ,
    CONSTRAINT chk_leave_date CHECK (leave_date IS NULL OR leave_date >= join_date)
);

--E6
CREATE TABLE messages (
    message_id uuid REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE PRIMARY KEY,
    chat_id uuid NOT NULL REFERENCES chats(chat_id) ON DELETE CASCADE ON UPDATE CASCADE,
    author_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    c_type content_type NOT NULL DEFAULT 'text',
    m_status message_status NOT NULL DEFAULT 'sent'
);

--E7
CREATE TABLE version_of_messages (
    message_id uuid NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE ON UPDATE CASCADE,
    version_number BIGINT NOT NULL CHECK (version_number >= 0),
    content text,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    editor_id uuid REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    change_reason text,
    v_type version_type NOT NULL DEFAULT 'original',
    CONSTRAINT pk_version_of_messages PRIMARY KEY (message_id, version_number)
);

--E8
CREATE TABLE attachments (
    attachment_id uuid REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE PRIMARY KEY,
    message_id uuid NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE ON UPDATE CASCADE,
    a_type attachment_type NOT NULL,
    name text NOT NULL,
    size BIGINT NOT NULL CHECK (size >= 0),
    path text NOT NULL,
    a_status attachment_status NOT NULL DEFAULT 'uploading'
);

--E9
CREATE TABLE attachment_representations (
    attachment_id uuid NOT NULL REFERENCES attachments(attachment_id) ON DELETE CASCADE ON UPDATE CASCADE,
    format text NOT NULL,
    size BIGINT NOT NULL CHECK (size >= 0),
    path text NOT NULL,
    r_status representation_status NOT NULL DEFAULT 'not_ready',
    CONSTRAINT pk_attachment_representations PRIMARY KEY (attachment_id, format)
);

--E10
CREATE TABLE delivery_events (
    event_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id uuid NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE ON UPDATE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE ON UPDATE CASCADE,
    previous_event_id uuid REFERENCES delivery_events(event_id) ON DELETE SET NULL ON UPDATE CASCADE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    d_type delivery_event_type NOT NULL
);

--E11
CREATE TABLE reactions (
    message_id uuid NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    reaction text NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_reactions PRIMARY KEY (message_id, user_id, reaction)
);

--E12
CREATE TABLE complaints (
    complaint_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    object_id uuid NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE,
    complainant_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    description text NOT NULL,
    filed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    c_status complaint_status NOT NULL DEFAULT 'filed'
);

--E13
CREATE TABLE decisions (
    decision_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    object_id uuid NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    complaint_id uuid NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE ON UPDATE CASCADE,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    d_type decision_type NOT NULL,
    d_status decision_status NOT NULL DEFAULT 'in_queue'
);

--E14
CREATE TABLE admin_actions (
    action_id uuid REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE PRIMARY KEY,
    object_id uuid NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    decision_id uuid NOT NULL REFERENCES decisions(decision_id) ON DELETE CASCADE ON UPDATE CASCADE,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    action_type admin_action_type NOT NULL,
    reason text,
    duration INTERVAL,
    CONSTRAINT chk_duration CHECK (duration IS NULL OR duration > INTERVAL '0 seconds')
);

--E15
CREATE TABLE audits (
    audit_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    object_id uuid NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    was_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    result audit_result NOT NULL,
    additional_info text
);