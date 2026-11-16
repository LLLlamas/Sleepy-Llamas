import { consultingServices } from './services';

const startingPrice = (id: string) =>
  `$${consultingServices.find((service) => service.id === id)?.price.toLocaleString('en-US')}`;

export const faqs = [
  {
    q: 'Is this only for families with newborns?',
    a: 'No. I work with expecting and new parents, families with toddlers and older siblings, and parents bringing a nanny or another caregiver into the home. We can focus on a daily routine, a transition, or how the adults caring for your children work together.',
  },
  {
    q: 'Which consultation should I choose?',
    a: `General family and nanny consultations start at ${startingPrice('general-family-consult')} for 60 minutes and focus on everyday routines, sibling transitions and caregiver questions. Newborn and postpartum consultations start at ${startingPrice('newborn-postpartum-consult')} for 60 minutes and focus on preparation, early care and adjusting after birth. Tell me what is happening if you are unsure; I will help you choose before you commit.`,
  },
  {
    q: 'What is the difference between a fit call and a paid consultation?',
    a: 'A free 15-minute fit call is a chance to meet, check availability and decide which service fits. A paid consultation includes preparation, time to work through your specific situation, a written plan and the follow-up described in your package.',
  },
  {
    q: 'Can my partner, nanny or a grandparent join?',
    a: 'Yes. Co-parents are welcome in parent consultations. The caregiver training session includes up to two caregivers, with family preferences, hands-on practice and a shared handoff. Let me know who will join so we can use the time well.',
  },
  {
    q: 'Is nanny training a professional certification?',
    a: 'The session helps your family and caregiver put a consistent care routine into practice. It is not an accredited professional certification or an infant CPR certification course. We can identify any separate training your caregiver needs.',
  },
  {
    q: 'Can we meet at home or speak remotely?',
    a: 'Phone and video consultations are available. I am based in Queens and arrange home visits in nearby NYC neighborhoods. Share your neighborhood and preferred timing; I will confirm travel, availability and any additional cost before booking.',
  },
  {
    q: 'What happens after I send a request?',
    a: 'I review your request personally and aim to reply within two business days. We confirm the service, time, scope and final price in writing before payment. Sending an inquiry does not reserve an appointment or overnight dates.',
  },
  {
    q: 'What if our plans change or we need more help?',
    a: 'We agree on scheduling, rescheduling and cancellation terms before payment. Packages include a defined follow-up window. Additional calls or home support can be arranged at the published starting rates, subject to availability.',
  },
  {
    q: 'Do you still offer overnight care?',
    a: 'Yes. Overnight doula support remains a separate service with its own calendar and packages. You can ask about nights alongside a consultation or request overnight support on its own.',
  },
  {
    q: 'Can you help with a child who has additional care needs?',
    a: 'I have experience supporting families who follow specialist care plans. We first discuss whether my experience and role fit your needs. I follow parent and provider instructions; my consultations do not replace medical, developmental or mental-health assessment and treatment.',
  },
  {
    q: 'Can employer benefits, an HSA or an FSA reimburse the service?',
    a: 'Eligibility depends on your plan, the specific service and its provider requirements. Confirm coverage with your plan administrator before booking. I can provide an accurate itemized receipt; reimbursement is not guaranteed.',
  },
];
