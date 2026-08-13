import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Página "Nosotros": historia, misión y equipo (#13 página complementaria). */
@Component({
  selector: 'app-nosotros',
  imports: [RouterLink],
  templateUrl: './nosotros.html',
  styleUrl: './nosotros.css',
})
export class Nosotros {}
