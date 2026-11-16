import type { ServicePageContent } from '../lib/servicePage';

export const homeVisitPage = {
  slug: 'first-days-home-visit',
  serviceId: 'home-consult',
  title: 'First Days Home Newborn Visit in Queens | Sleepy Llamas',
  description: 'Hands-on newborn guidance with Catalina in your own home. Practice everyday care, organize supplies, and leave with a written family handoff. Queens and nearby NYC.',
  eyebrow: 'First Days Home Visit',
  heading: 'A newborn home visit, shaped around your family.',
  intro: 'The first days home bring a lot of small questions at once. I can work beside you as you practice everyday baby care, arrange the things you reach for most, and decide how your household will share the next day and night. For your first baby or your next one, we start with what would help your family today.',
  fitHeading: 'For the practical pieces of coming home',
  situations: [
    {
      title: 'Your first baby is home',
      body: 'You have the supplies and plenty of advice. Now you want someone beside you as you practice changing, settling, preparing for feeds, and keeping a simple record of care.',
    },
    {
      title: 'Your family is growing again',
      body: 'The older child still has meals, pickups, and bedtime. We can look at your real space and routine, then share the care between the adults helping you.',
    },
    {
      title: 'You are making room for recovery',
      body: 'Following a C-section or another birth recovery, practical help can mean arranging supplies within reach, clarifying who handles which tasks, and making a workable rest plan around your care team’s instructions.',
    },
    {
      title: 'Your helpers need a shared plan',
      body: 'A partner, grandparent, or other caregiver can join the visit. We can practice the same routines together and write down the details you want carried into the next handoff.',
    },
  ],
  sessionHeading: 'What we can work through together',
  sessionSteps: [
    {
      title: 'Choose your priorities before the visit',
      body: 'Tell me your family’s stage, neighborhood, and what feels hardest to manage. We agree on three priorities, the people joining us, and the timing and travel details before confirming your appointment.',
    },
    {
      title: 'Practice in the space you actually use',
      body: 'We work through those priorities at your pace: everyday newborn care, a more useful feeding or changing station, soothing, care records, or sharing tasks between adults. I follow your family’s preferences and your baby’s provider guidance.',
    },
    {
      title: 'Make the next handoff clear',
      body: 'We bring the practical pieces into a written family handoff: what you practiced, who is doing what, what still needs clarification, and the next steps to try. The included follow-up call gives us a chance to talk through how the plan is working.',
    },
  ],
  deliverable: {
    title: 'A family handoff you can return to',
    intro: 'Your written handoff keeps the useful details together so you and the other adults caring for your baby have a shared reference.',
    items: [
      'The priorities you chose and the routines you practiced together',
      'Your household’s care tasks and the adult responsible for each one',
      'A simple way to record feeds, changes, rest, and notes for the next caregiver',
      'Questions to take back to your baby’s or your own care team',
      'The next steps you agreed on and the focus for your included follow-up',
    ],
    note: 'The handoff reflects your visit and your family’s instructions. It is a practical care reference, rather than a medical assessment or a fixed newborn schedule.',
  },
  boundaries: [
    'This is a focused practical visit with you and your family. Longer childcare coverage, overnight care, and a household-cleaning service are separate needs.',
    'Medical recovery, wound care, medication, feeding treatment, and individual safety concerns stay with your healthcare professionals. I help you organize everyday care around their guidance.',
    'Visits are based in Queens and nearby NYC neighborhoods. Travel, timing, scope, and final price are confirmed before booking; an inquiry does not reserve a time.',
    'A newborn’s needs change. We use responsive care and realistic household planning, with no promise of a particular feeding or sleep outcome.',
  ],
  faqs: [
    {
      q: 'Can I arrange a visit before my baby arrives?',
      a: 'Yes. We can discuss a possible visit and your priorities during pregnancy. Tell me your expected timing and neighborhood; the actual appointment depends on availability and is confirmed with you. A fit call does not reserve a birth-date window.',
    },
    {
      q: 'Is this useful for a second or third baby?',
      a: 'Yes. We can focus on the parts that are different this time: another child’s day, less space, a different feeding plan, or a new mix of caregivers. You choose what would make this transition easier.',
    },
    {
      q: 'Can you help us organize things after a C-section?',
      a: 'I can help arrange everyday supplies, plan care tasks with your helpers, and make room for parent rest while you follow your discharge instructions. Your healthcare team handles medical recovery questions and any restrictions specific to you.',
    },
    {
      q: 'Does this replace the newborn or postpartum medical visit?',
      a: 'No. Keep your baby’s and your own healthcare appointments. This visit is practical, non-medical family support. NYC also offers no-cost home-visiting services for eligible families; the city’s program page below explains how to check eligibility.',
    },
    {
      q: 'Can my partner or another caregiver join?',
      a: 'Yes. Share who you would like to include before the visit so we can plan around your priorities. If the main goal is teaching a nanny or several caregivers your household’s routines, Nanny & Caregiver Coaching may be the better fit.',
    },
    {
      q: 'What happens after the visit, or if we want another day?',
      a: 'Your visit includes a written family handoff and one 20-minute follow-up call within 7 days. Existing home-visit families can ask about an additional home-support visit, subject to availability and a confirmed scope and price. It is arranged separately.',
    },
    {
      q: 'How do I request a visit?',
      a: 'Use the inquiry form and share your neighborhood, family stage, and a brief description of the help you want. I will respond within the published response window to discuss fit and timing. Please use your care provider for urgent health concerns.',
    },
  ],
  related: [
    { slug: 'newborn-postpartum-consultations', label: 'Newborn & Postpartum Consultations' },
    { slug: 'nanny-caregiver-coaching', label: 'Nanny & Caregiver Coaching' },
  ],
  resourceLinks: [
    {
      title: 'NYC Newborn Home Visiting Program',
      url: 'https://www.nyc.gov/site/doh/health/health-topics/pregnancy-newborn-visiting.page',
      description: 'The city offers no-cost home visits for eligible families. Read the current program details and how to check eligibility.',
    },
    {
      title: 'Understanding doula support',
      url: 'https://www.nyc.gov/site/doh/health/health-topics/doula-care.page',
      description: 'NYC Health explains non-medical doula support and lists community resources for families.',
    },
  ],
} satisfies ServicePageContent;
