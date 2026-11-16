// Shared public service catalogue. Prices are starting rates; scope and timing
// are confirmed personally before an appointment is booked.
export interface ConsultingService {
  id: string;
  title: string;
  price: number;
  duration: string;
  format: string;
  category: 'family' | 'newborn' | 'home' | 'training';
  description: string;
  bullets: string[];
  linkText: string;
  featured?: boolean;
}

export const consultingServices: ConsultingService[] = [
  {
    id: 'general-family-consult',
    title: 'Family Life Consultation',
    price: 175,
    duration: '60 minutes',
    format: 'Phone or video',
    category: 'family',
    description: 'A thoughtful conversation about the everyday things that make family life feel complicated: toddler routines, sibling transitions, caregiver communication, or finding a rhythm that works for everyone.',
    bullets: [
      'One main topic, with room for your questions',
      'A short written plan with practical next steps',
      'One clarification email within 7 days',
    ],
    linkText: 'Ask about a family consultation',
  },
  {
    id: 'newborn-postpartum-consult',
    title: 'Newborn & Postpartum Consultation',
    price: 250,
    duration: '60 minutes',
    format: 'Phone or video',
    category: 'newborn',
    featured: true,
    description: 'Dedicated doula support for preparing for your baby, navigating the first days home, or making newborn care feel more manageable. We focus on your baby, your recovery support, and the help your household needs.',
    bullets: [
      'Newborn care, settling, feeding logistics, and parent rest',
      'A personal written care and support plan',
      'One clarification email within 7 days',
    ],
    linkText: 'Ask about newborn support',
  },
  {
    id: 'first-weeks-plan',
    title: 'First Weeks Together',
    price: 450,
    duration: 'Support over 14 days',
    format: 'Phone or video',
    category: 'newborn',
    description: 'A little continuity while everything is changing. Prepare before your baby arrives or begin once you are home, with space to try your plan and talk through what needs adjusting.',
    bullets: [
      'One 60-minute newborn and postpartum consultation',
      'Two 20-minute follow-up calls and an updated written plan',
      'Two email question rounds during your 14 days of support',
    ],
    linkText: 'Plan our first weeks',
  },
  {
    id: 'home-consult',
    title: 'First Days Home Visit',
    price: 550,
    duration: '3 hours at home',
    format: 'In person · NYC',
    category: 'home',
    description: 'Let’s work through it together, in the space where you care for your baby. Practice everyday care, organize your feeding and changing stations, and make a realistic plan for the next day and night.',
    bullets: [
      'Three priorities chosen together before your visit',
      'Hands-on guidance and a written family handoff',
      'One 20-minute follow-up call within 7 days',
    ],
    linkText: 'Ask about a home visit',
  },
  {
    id: 'caregiver-training',
    title: 'Nanny & Caregiver Coaching',
    price: 595,
    duration: '3 hours at home',
    format: 'Up to 2 caregivers · NYC',
    category: 'training',
    description: 'Bring your nanny, grandparent, or co-parent into the same conversation. We practice your family’s care routines, clarify expectations, and build a handoff that helps everyone feel prepared.',
    bullets: [
      'Care routines for your child’s age, family preferences, and communication',
      'A shared family care guide and daily handoff template',
      'One 20-minute check-in within 7 days; family-specific coaching',
    ],
    linkText: 'Plan caregiver coaching',
  },
];

export const fitCall = {
  id: 'fit-call',
  title: 'Meet Catalina',
  price: 0,
  duration: '15 minutes',
  description: 'Not sure where to begin? We can talk about what you need, which service fits, and timing. Your personal care plan begins in a paid session.',
};

export const consultationAddOns = [
  { id: 'family-followup', title: 'Family consultation follow-up', price: 65, duration: '20 minutes', description: 'For an existing family consultation topic.' },
  { id: 'newborn-followup', title: 'Newborn & postpartum follow-up', price: 95, duration: '20 minutes', description: 'Dedicated doula support after your newborn consultation.' },
  { id: 'extra-home-day', title: 'An extra day of home support', price: 450, duration: '3 hours', description: 'For existing home-visit families, building on your care plan.' },
];

export const overnightServices = [
  { id: 'overnight-doula', title: 'Overnight Doula Support', description: 'Responsive newborn care, feeding logistics, and a clear morning handoff while your family rests.' },
  { id: 'overnight-sleep-training', title: 'Overnight Sleep Support', description: 'Gentle, age-appropriate routines shaped around your baby and your family’s care instructions.' },
];

// Existing overnight rates are retained.
export const overnightPackages = [
  { key: '4-nights', name: 'Starter', nights: 4, timeframe: 'Over 2 weeks', price: 2480, specialPrice: 2600 },
  { key: '8-nights', name: 'Standard', nights: 8, timeframe: 'Over 2–4 weeks', price: 4800, specialPrice: 5200 },
  { key: '12-nights', name: 'Extended', nights: 12, timeframe: 'Over 2–5 weeks', price: 6900, specialPrice: 7500 },
  { key: '16-nights', name: 'Comprehensive', nights: 16, timeframe: 'Over 6–8 weeks', price: 9000, specialPrice: 9800 },
];
