-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create user role enum
CREATE TYPE user_role AS ENUM ('student', 'faculty', 'admin');

-- Create profiles table for user information
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'student',
    department TEXT,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Create classrooms table
CREATE TABLE public.classrooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_name TEXT NOT NULL UNIQUE,
    capacity INTEGER NOT NULL CHECK (capacity > 0),
    equipment TEXT[], -- Array of equipment like ['projector', 'smartboard', 'audio_system']
    location TEXT NOT NULL,
    availability_status BOOLEAN DEFAULT true,
    remarks TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create courses table
CREATE TABLE public.courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code TEXT NOT NULL UNIQUE,
    course_name TEXT NOT NULL,
    department TEXT NOT NULL,
    credits INTEGER DEFAULT 3 CHECK (credits > 0),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create timetable table
CREATE TABLE public.timetable (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.classrooms(id) ON DELETE CASCADE,
    day_of_week TEXT NOT NULL CHECK (day_of_week IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    semester TEXT NOT NULL,
    academic_year TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT valid_time_range CHECK (end_time > start_time)
);

-- Create feedback table
CREATE TABLE public.feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classrooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timetable ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view all profiles" 
ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update their own profile" 
ON public.profiles FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile" 
ON public.profiles FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Classrooms policies (read access for all, admin-only for modifications)
CREATE POLICY "Anyone can view classrooms" 
ON public.classrooms FOR SELECT USING (true);

CREATE POLICY "Admins can manage classrooms" 
ON public.classrooms FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- Courses policies
CREATE POLICY "Anyone can view courses" 
ON public.courses FOR SELECT USING (true);

CREATE POLICY "Admins can manage courses" 
ON public.courses FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- Timetable policies
CREATE POLICY "Anyone can view timetable" 
ON public.timetable FOR SELECT USING (true);

CREATE POLICY "Admins and faculty can manage timetable" 
ON public.timetable FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'faculty')
    )
);

-- Feedback policies
CREATE POLICY "Users can view their own feedback" 
ON public.feedback FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create feedback" 
ON public.feedback FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all feedback" 
ON public.feedback FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- Create function to handle new user registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (user_id, name, email, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
        NEW.email,
        'student'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new user registration
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create function to update timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updating timestamps
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_classrooms_updated_at
    BEFORE UPDATE ON public.classrooms
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_courses_updated_at
    BEFORE UPDATE ON public.courses
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_timetable_updated_at
    BEFORE UPDATE ON public.timetable
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_feedback_updated_at
    BEFORE UPDATE ON public.feedback
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Create indexes for better performance
CREATE INDEX idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX idx_profiles_role ON public.profiles(role);
CREATE INDEX idx_timetable_faculty_id ON public.timetable(faculty_id);
CREATE INDEX idx_timetable_room_id ON public.timetable(room_id);
CREATE INDEX idx_timetable_course_id ON public.timetable(course_id);
CREATE INDEX idx_timetable_day_time ON public.timetable(day_of_week, start_time, end_time);
CREATE INDEX idx_feedback_user_id ON public.feedback(user_id);

-- Insert sample data
INSERT INTO public.classrooms (room_name, capacity, equipment, location, availability_status, remarks) VALUES
('Room A101', 50, '{"projector", "whiteboard", "air_conditioning"}', 'Building A, Floor 1', true, 'Standard classroom with modern amenities'),
('Room B201', 30, '{"smart_board", "audio_system", "projector"}', 'Building B, Floor 2', true, 'Small seminar room'),
('Lab C301', 25, '{"computers", "projector", "air_conditioning"}', 'Building C, Floor 3', true, 'Computer lab'),
('Auditorium D001', 200, '{"sound_system", "projector", "stage", "microphones"}', 'Building D, Ground Floor', true, 'Large auditorium for events'),
('Room A102', 40, '{"projector", "whiteboard"}', 'Building A, Floor 1', false, 'Under maintenance');

INSERT INTO public.courses (course_code, course_name, department, credits, description) VALUES
('CS101', 'Introduction to Computer Science', 'Computer Science', 3, 'Basic concepts of computer science and programming'),
('MATH201', 'Calculus II', 'Mathematics', 4, 'Advanced calculus concepts and applications'),
('ENG101', 'English Composition', 'English', 3, 'Academic writing and communication skills'),
('PHYS201', 'Physics II', 'Physics', 4, 'Electricity, magnetism, and waves'),
('BIO101', 'General Biology', 'Biology', 3, 'Introduction to biological concepts');