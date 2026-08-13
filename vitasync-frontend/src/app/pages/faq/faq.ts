import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Página de preguntas frecuentes (#13 página complementaria). */
@Component({
  selector: 'app-faq',
  imports: [RouterLink],
  templateUrl: './faq.html',
  styleUrl: './faq.css',
})
export class Faq {}
